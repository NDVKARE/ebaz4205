import zipfile
from pathlib import Path

root = Path('/mnt/e/EBAZ4205-PetaLinux-main/EBAZ4205-PetaLinux-main')
for path in [root / 'petalinux/project-spec/hw-description/system.xsa', root / 'vivado/blockdesign_1_wrapper.xsa']:
    print(path)
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if name.endswith('.hwh'):
                for line in archive.read(name).decode(errors='replace').splitlines():
                    if 'VERSION' in line[:120] or 'TIMESTAMP' in line[:120]:
                        print(line[:250])
                        if 'EDKSYSTEM' in line:
                            break
