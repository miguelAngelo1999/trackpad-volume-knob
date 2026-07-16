# Mac Trackpad Fix release infrastructure constants

GDRIVE_FOLDER_ID    = '1-DNwVKkUOtqGMHPBCULZUSA919kjOBgc'
LUX_SERVICE_ACCOUNT = '/Users/virgoh/lux/lucky-science-501221-c2-7248ccec3971.json'
LUX_OAUTH_CLIENT    = '/Users/virgoh/lux/scripts/oauth_client.json'
LUX_TOKEN_CACHE     = '/Users/virgoh/lux/scripts/.oauth_token.json'
GITHUB_REPO         = 'miguelAngelo1999/trackpad-volume-knob'
APP_NAME            = 'Mac Trackpad Fix'
PKG_BASENAME        = 'MacTrackpadFix-{version}.pkg'

# Stable file IDs — content is overwritten in-place each release, IDs never change
APPCAST_FILE_ID     = '1Tm6XmjizYSJ-NWECo1X8Quj2XjhArT3y'
PKG_FILE_ID         = '1K8Qir_1TdmJpFpn-BJfgRfX0qd4Z-5kd'

# Stable download URLs (derived from file IDs above)
APPCAST_URL         = f'https://drive.usercontent.google.com/download?id={APPCAST_FILE_ID}&export=download&confirm=t'
PKG_URL             = f'https://drive.usercontent.google.com/download?id={PKG_FILE_ID}&export=download&confirm=t'
