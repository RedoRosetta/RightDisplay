# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Read-only host identity tests. No audio/device calls or service changes."""
from pathlib import Path
import json,re,subprocess,tempfile
root=Path(__file__).resolve().parent.parent
source=(root/'AudioVirtualDevice/Broker/main.c').read_text()
requirement=json.loads(re.search(r'producerRequirement = (".*");',source).group(1))
candidates=[('/usr/sbin/coreaudiod',True),('/System/Library/Frameworks/CoreAudio.framework/Versions/A/XPCServices/com.apple.audio.Core-Audio-Driver-Service.helper.xpc',True),('/bin/ls',False),('/Applications/Right Display.app',False),('/Library/PrivilegedHelperTools/com.rightdisplay.audio.Transport',False)]
for path,expected in candidates:
    if not Path(path).exists(): raise SystemExit('Fixture unavailable: '+path)
    result=subprocess.run(['codesign','--verify','-R','='+requirement,path],capture_output=True)
    assert (result.returncode==0)==expected,(path,result.stderr)
print('Actual host signatures: 5 accept/reject assertions PASS')
s=(root/'RightDisplay/Services/AudioDeviceProvider.swift').read_text()
error=s[s.index('enum AudioBridgeError:'):s.index('enum AudioBridgeJSON')]
out=Path(tempfile.mkdtemp(prefix='RightDisplay-host-error-test-',dir='/private/tmp'))
file=out/'test.swift';file.write_text(error+'\nprecondition(String(describing: AudioBridgeError.message("TRANSPORT_PRODUCER_UNAVAILABLE")) == "TRANSPORT_PRODUCER_UNAVAILABLE")\nprint("Production error description: 1 assertion PASS")\n')
subprocess.run(['xcrun','swiftc','-module-cache-path',str(out/'cache'),str(file),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True)
