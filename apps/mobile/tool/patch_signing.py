"""Add a release signingConfig that reads its keystore from the environment.

Run from bootstrap_platforms.sh. Writes no key material anywhere: the paths
and passwords are read by Gradle at build time from environment variables.
"""

import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

signing = '''
    signingConfigs {
        release {
            def ks = System.getenv("FITTRACK_KEYSTORE")
            if (ks != null && !ks.isEmpty() && file(ks).exists()) {
                storeFile = file(ks)
                storePassword = System.getenv("FITTRACK_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("FITTRACK_KEY_ALIAS")
                keyPassword = System.getenv("FITTRACK_KEY_PASSWORD")
            }
        }
    }
'''

marker = "    buildTypes {"
if signing.strip() not in text:
    text = text.replace(marker, signing + marker, 1)

text = text.replace(
    "            signingConfig = signingConfigs.debug",
    '            signingConfig = System.getenv("FITTRACK_KEYSTORE") '
    "? signingConfigs.release : signingConfigs.debug",
    1,
)
path.write_text(text)
