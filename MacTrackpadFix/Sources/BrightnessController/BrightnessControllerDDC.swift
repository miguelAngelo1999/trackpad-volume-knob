// BrightnessControllerDDC.swift
// DDC brightness read/write for external displays.
//
// arm64 path:  IOAVService via dlopen/dlsym from IOKit.framework
// Intel path:  IOFramebuffer I2C (IOFBGetI2CInterfaceCount / IOI2CSendRequest)
//
// Ported from mac-mouse-fix ScrollOutputUtility.m.

import AppKit
import CoreGraphics
import IOKit
import IOKit.graphics
import IOKit.i2c
import Foundation

// MARK: - C function pointer types

private typealias IOAVServiceRef     = CFTypeRef
private typealias IOAVServiceCreateFn   = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
private typealias IOAVServiceWriteI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
private typealias IOAVServiceReadI2CFn  = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
private typealias CoreDisplayInfoFn     = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

// MARK: - BrightnessControllerDDC

final class BrightnessControllerDDC {

    private var avCreate:  IOAVServiceCreateFn?
    private var avWrite:   IOAVServiceWriteI2CFn?
    private var avRead:    IOAVServiceReadI2CFn?
    private var cdInfo:    CoreDisplayInfoFn?

    private var serviceCache:    [CGDirectDisplayID: CFTypeRef?] = [:]
    private var brightnessCache: [CGDirectDisplayID: Int]        = [:]

    // MARK: Init

    init() { loadSymbols() }

    private func loadSymbols() {
        func sym<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T?.self)
        }
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        avCreate = sym(iokit, "IOAVServiceCreateWithService")
        avWrite  = sym(iokit, "IOAVServiceWriteI2C")
        avRead   = sym(iokit, "IOAVServiceReadI2C")

        let cd = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
        cdInfo = sym(cd, "CoreDisplay_DisplayCreateInfoDictionary")
    }

    // MARK: - Public API

    func readBrightness(displayID: CGDirectDisplayID) -> Int {
        if let svc = avService(for: displayID) { return readDDC(service: svc) }
        return readDDCViaFramebuffer(displayID: displayID)
    }

    func writeBrightness(_ value: Int, displayID: CGDirectDisplayID) {
        let v = Swift.min(100, Swift.max(0, value))
        guard brightnessCache[displayID] != v else { return }
        brightnessCache[displayID] = v
        if let svc = avService(for: displayID) {
            writeDDC(v, service: svc)
        } else {
            writeDDCViaFramebuffer(v, displayID: displayID)
        }
    }

    func invalidateCaches() {
        serviceCache.removeAll()
        brightnessCache.removeAll()
    }

    // MARK: - IOAVService cache

    private func avService(for displayID: CGDirectDisplayID) -> CFTypeRef? {
        if let cached = serviceCache[displayID] { return cached }
        rebuildServiceMappings()
        return serviceCache[displayID] ?? nil
    }

    // MARK: - DDC write (arm64 IOAVService)

    private func writeDDC(_ value: Int, service: CFTypeRef) {
        guard let fn = avWrite else { return }
        var packet: [UInt8] = [0x84, 0x03, 0x10,
                               UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0]
        packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        let copy = packet
        // Retain manually — crossing concurrency boundary with CFTypeRef
        let retained = Unmanaged.passRetained(service as AnyObject)
        DispatchQueue.global(qos: .userInteractive).async {
            let obj = retained.takeRetainedValue() as CFTypeRef
            var buf = copy
            _ = fn(obj, 0x37, 0x51, &buf, UInt32(buf.count))
        }
    }

    // MARK: - DDC read (arm64)

    private func readDDC(service: CFTypeRef) -> Int {
        guard let writeFn = avWrite, let readFn = avRead else { return 50 }
        var send: [UInt8] = [0x82, 0x01, 0x10, 0]
        send[3] = 0x6E ^ 0x51 ^ send[0] ^ send[1] ^ send[2]
        usleep(10_000)
        guard writeFn(service, 0x37, 0x51, &send, UInt32(send.count)) == kIOReturnSuccess else { return 50 }
        usleep(50_000)
        var reply = [UInt8](repeating: 0, count: 11)
        guard readFn(service, 0x37, 0, &reply, UInt32(reply.count)) == kIOReturnSuccess else { return 50 }
        var chk: UInt8 = 0x50
        for i in 0..<10 { chk ^= reply[i] }
        guard chk == reply[10] else { return 50 }
        return Swift.min(100, Swift.max(0, (Int(reply[8]) << 8) | Int(reply[9])))
    }

    // MARK: - Intel IOFramebuffer I2C fallback

    private func framebufferPort(for displayID: CGDirectDisplayID) -> io_service_t {
        guard CGDisplayIsBuiltin(displayID) == 0 else { return IO_OBJECT_NULL }
        var iter: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
              IOServiceMatching("IODisplayConnect"), &iter) == KERN_SUCCESS else { return IO_OBJECT_NULL }
        let vendorID  = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)
        var result: io_service_t = IO_OBJECT_NULL
        while result == IO_OBJECT_NULL {
            let svc = IOIteratorNext(iter)
            guard svc != IO_OBJECT_NULL else { break }
            if let ref = IODisplayCreateInfoDictionary(svc, IOOptionBits(kIODisplayOnlyPreferredName)) {
                let d = ref.takeRetainedValue() as NSDictionary
                let v = (d[kDisplayVendorID]  as? UInt32) ?? 0
                let p = (d[kDisplayProductID] as? UInt32) ?? 0
                if v == vendorID && p == productID {
                    var parent: io_service_t = IO_OBJECT_NULL
                    IORegistryEntryGetParentEntry(svc, kIOServicePlane, &parent)
                    result = parent
                }
            }
            IOObjectRelease(svc)
        }
        IOObjectRelease(iter)
        return result
    }

    private func writeDDCViaFramebuffer(_ value: Int, displayID: CGDirectDisplayID) {
        let fb = framebufferPort(for: displayID)
        guard fb != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(fb) }
        var data: [UInt8] = [0x51, 0x84, 0x03, 0x10,
                             UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0]
        data[6] = data[0]^data[1]^data[2]^data[3]^data[4]^data[5]^0x6E
        data.withUnsafeMutableBytes { ptr in
            var req = IOI2CRequest()
            req.commFlags = 0
            req.sendAddress = 0x6E
            req.sendTransactionType = UInt32(kIOI2CSimpleTransactionType)
            req.sendBuffer = vm_address_t(UInt(bitPattern: ptr.baseAddress!))
            req.sendBytes  = UInt32(ptr.count)
            req.replyTransactionType = UInt32(kIOI2CNoTransactionType)
            req.replyBytes = 0
            usleep(10_000)
            _ = sendI2C(fb: fb, request: &req)
        }
    }

    private func readDDCViaFramebuffer(displayID: CGDirectDisplayID) -> Int {
        let fb = framebufferPort(for: displayID)
        guard fb != IO_OBJECT_NULL else { return 50 }
        defer { IOObjectRelease(fb) }
        var send: [UInt8] = [0x51, 0x82, 0x01, 0x10, 0]
        send[4] = send[0]^send[1]^send[2]^send[3]^0x6E
        var reply = [UInt8](repeating: 0, count: 11)
        var result = 50
        var replyBuf = [UInt8](repeating: 0, count: 11)
        var success = false
        send.withUnsafeMutableBytes { sendPtr in
            replyBuf.withUnsafeMutableBytes { replyPtr in
                var req = IOI2CRequest()
                req.commFlags = 0
                req.sendAddress = 0x6E
                req.sendTransactionType = UInt32(kIOI2CSimpleTransactionType)
                req.sendBuffer = vm_address_t(UInt(bitPattern: sendPtr.baseAddress!))
                req.sendBytes  = UInt32(sendPtr.count)
                req.replyAddress = 0x6F
                req.replyTransactionType = UInt32(kIOI2CDDCciReplyTransactionType)
                req.replyBuffer = vm_address_t(UInt(bitPattern: replyPtr.baseAddress!))
                req.replyBytes  = UInt32(replyPtr.count)
                req.minReplyDelay = 50_000_000
                usleep(10_000)
                success = sendI2C(fb: fb, request: &req)
            }
        }
        if success {
            var chk: UInt8 = 0x50
            for i in 0..<10 { chk ^= replyBuf[i] }
            if chk == replyBuf[10] {
                result = Swift.min(100, Swift.max(0, (Int(replyBuf[8]) << 8) | Int(replyBuf[9])))
            }
        }
        return result
    }

    @discardableResult
    private func sendI2C(fb: io_service_t, request: inout IOI2CRequest) -> Bool {
        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(fb, &busCount) == KERN_SUCCESS, busCount > 0 else { return false }
        for bus in 0..<busCount {
            var iface: io_service_t = IO_OBJECT_NULL
            guard IOFBCopyI2CInterfaceForBus(fb, bus, &iface) == KERN_SUCCESS else { continue }
            var conn: IOI2CConnectRef? = nil
            guard IOI2CInterfaceOpen(iface, 0, &conn) == KERN_SUCCESS, let c = conn else {
                IOObjectRelease(iface); continue
            }
            let r = IOI2CSendRequest(c, 0, &request)
            IOI2CInterfaceClose(c, 0)
            IOObjectRelease(iface)
            if r == KERN_SUCCESS && request.result == kIOReturnSuccess { return true }
        }
        return false
    }

    // MARK: - EDID-based IOAVService matching (arm64)

    private func rebuildServiceMappings() {
        guard let createFn = avCreate else { return }

        struct Info {
            let service: CFTypeRef
            let edidUUID: String
            let productName: String
            let serial: Int64
            let ioLocation: String
            let order: Int
        }
        var infos: [Info] = []

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        var iter: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryEntryCreateIterator(root, kIOServicePlane,
              IOOptionBits(kIORegistryIterateRecursively), &iter) == KERN_SUCCESS else {
            IOObjectRelease(root); return
        }
        IOObjectRelease(root)

        var curEdidUUID = "", curProductName = "", curSerial: Int64 = 0, curLocation = ""
        var order = 0
        var nameBuf = [CChar](repeating: 0, count: 256)

        while true {
            let entry = IOIteratorNext(iter)
            guard entry != IO_OBJECT_NULL else { break }
            guard IORegistryEntryGetName(entry, &nameBuf) == KERN_SUCCESS else {
                IOObjectRelease(entry); continue
            }
            let name = String(decoding: nameBuf.prefix(while: { $0 != 0 }).map({ UInt8(bitPattern: $0) }), as: UTF8.self)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                order += 1
                curEdidUUID = ""; curProductName = ""; curSerial = 0; curLocation = ""
                if let v = IORegistryEntryCreateCFProperty(entry, "EDID UUID" as CFString,
                   kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) {
                    curEdidUUID = (v.takeRetainedValue() as? String) ?? ""
                }
                var pathBuf = [CChar](repeating: 0, count: 512)
                if IORegistryEntryGetPath(entry, kIOServicePlane, &pathBuf) == KERN_SUCCESS {
                    curLocation = String(decoding: pathBuf.prefix(while: { $0 != 0 }).map({ UInt8(bitPattern: $0) }), as: UTF8.self)
                }
                if let a = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString,
                   kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) {
                    if let d = a.takeRetainedValue() as? NSDictionary,
                       let pa = d["ProductAttributes"] as? NSDictionary {
                        curProductName = (pa["ProductName"] as? String) ?? ""
                        curSerial = (pa["SerialNumber"] as? NSNumber)?.int64Value ?? 0
                    }
                }
            }

            if name == "DCPAVServiceProxy" {
                var loc = ""
                if let v = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0) {
                    loc = (v.takeRetainedValue() as? String) ?? ""
                }
                if loc == "External",
                   let svcRef = createFn(kCFAllocatorDefault, entry) {
                    infos.append(Info(
                        service: svcRef.takeRetainedValue(),
                        edidUUID: curEdidUUID, productName: curProductName,
                        serial: curSerial, ioLocation: curLocation, order: order
                    ))
                }
            }
            IOObjectRelease(entry)
        }
        IOObjectRelease(iter)

        // Score & assign
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &displays, &count)

        struct Candidate { let did: CGDirectDisplayID; let idx: Int; let score: Int }
        var candidates: [Candidate] = []

        for d in 0..<Int(count) {
            let did = displays[d]
            guard CGDisplayIsBuiltin(did) == 0 else { continue }
            for (i, info) in infos.enumerated() {
                let s = matchScore(did: did, edidUUID: info.edidUUID,
                                   ioLocation: info.ioLocation, productName: info.productName,
                                   serial: info.serial)
                candidates.append(Candidate(did: did, idx: i, score: s))
            }
        }
        candidates.sort { $0.score > $1.score }

        serviceCache.removeAll()
        var takenDids = Set<CGDirectDisplayID>()
        var takenIdxs = Set<Int>()

        for c in candidates {
            guard c.score > 0, !takenDids.contains(c.did), !takenIdxs.contains(c.idx) else { continue }
            takenDids.insert(c.did)
            takenIdxs.insert(c.idx)
            serviceCache[c.did] = infos[c.idx].service
        }

        for d in 0..<Int(count) {
            let did = displays[d]
            if CGDisplayIsBuiltin(did) == 0 && serviceCache[did] == nil {
                serviceCache[did] = .some(nil)
            }
        }
    }

    private func matchScore(did: CGDirectDisplayID, edidUUID: String,
                            ioLocation: String, productName: String, serial: Int64) -> Int {
        guard let fn = cdInfo, let ref = fn(did) else { return 0 }
        let dict = ref.takeRetainedValue() as NSDictionary
        var score = 0

        if !ioLocation.isEmpty,
           let loc = dict[kIODisplayLocationKey] as? String,
           loc == ioLocation { score += 10 }

        if edidUUID.count >= 8 {
            let vendorHex = String(format: "%04X", CGDisplayVendorNumber(did))
            if edidUUID.hasPrefix(vendorHex) { score += 1 }
            let pid = UInt16(CGDisplayModelNumber(did))
            let productHex = String(format: "%02X%02X", pid & 0xFF, (pid >> 8) & 0xFF)
            if edidUUID.dropFirst(4).hasPrefix(productHex) { score += 1 }
        }

        if !productName.isEmpty,
           let names = dict["DisplayProductName"] as? NSDictionary,
           let n = (names["en_US"] as? String) ?? (names.allValues.first as? String),
           n.caseInsensitiveCompare(productName) == .orderedSame { score += 1 }

        if serial != 0,
           let s = dict[kDisplaySerialNumber] as? Int64,
           s == serial { score += 1 }

        return score
    }
}
