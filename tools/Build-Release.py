"""Build a release from tracked app files; never sweep a user's working folder.

Run after committing the intended source. Outputs an archive and candidate update
manifest. Publishing is separate and must follow Windows validation.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
ROOT_EXTENSIONS = {'.ps1', '.cs', '.xaml', '.ico', '.svg', '.cmd'}
ROOT_DOCUMENTS = {'README.md', 'RELEASE-NOTES.md', 'TEST-TONIGHT.md', 'version.json'}


def release_paths():
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    paths = []
    for name in filter(None, names):
        relative = pathlib.PurePosixPath(name)
        included = (len(relative.parts) == 1 and
                    (relative.suffix in ROOT_EXTENSIONS or name in ROOT_DOCUMENTS))
        included |= relative.parts[0] in {'assets', 'vendor'}
        if not included:
            continue
        path = ROOT / relative
        if not path.is_file() or path.is_symlink():
            raise ValueError(f'Missing or linked release input: {name}')
        paths.append(name)
    for required in ('PC-Insight.ps1', 'Start-App.ps1', 'Install.ps1', 'MainWindow.xaml',
                     'Reliability.ps1', 'EnduranceResultsUI.ps1', 'SessionLibrary.ps1', 'SessionLibraryUI.ps1', 'SessionReport.ps1', 'GpuAutoTune.ps1', 'version.json',
                     'vendor/LibreHardwareMonitor/hashes.json'):
        if required not in paths:
            raise ValueError(f'Required file is not tracked: {required}')
    return sorted(paths)


def build(output):
    version = json.loads((ROOT / 'version.json').read_text(encoding='utf-8-sig'))['Version']
    if not version or any(c not in '0123456789.' for c in version):
        raise ValueError('Invalid version')
    for item in json.loads((ROOT / 'vendor/LibreHardwareMonitor/hashes.json').read_text(encoding='utf-8-sig')):
        data = (ROOT / 'vendor/LibreHardwareMonitor' / item['Name']).read_bytes()
        if hashlib.sha256(data).hexdigest().upper() != item['SHA256'].upper():
            raise ValueError(f'Vendor integrity check failed: {item["Name"]}')
    paths = release_paths()
    output.mkdir(parents=True, exist_ok=True)
    archive = output / 'PC-Insight-Windows-Preview.zip'
    records = []
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name in paths:
            data = (ROOT / name).read_bytes()
            entry = zipfile.ZipInfo('PC-Insight/' + name, date_time=(2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            bundle.writestr(entry, data)
            records.append({'Path': name, 'Bytes': len(data), 'SHA256': hashlib.sha256(data).hexdigest()})
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip():
            raise ValueError('Archive integrity check failed')
        for record in records:
            if hashlib.sha256(bundle.read('PC-Insight/' + record['Path'])).hexdigest() != record['SHA256']:
                raise ValueError('Archive round-trip mismatch')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT))
    manifest = {'schema': 1, 'appId': 'PCInsight.PerUser', 'version': version,
                'downloadUrl': f'https://github.com/IGN1TE/pc-insight/releases/download/v{version}/PC-Insight-Windows-Preview.zip',
                'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                'sizeBytes': archive.stat().st_size,
                'releaseNotes': 'Fixes GPU baselines being rejected when only CPU temperatures are unavailable. GPU readings remain usable, missing CPU coverage is shown, and real sensor errors still block tuning. Start a fresh automatic scan baseline.'}
    (output / 'update.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (output / 'package-audit.json').write_text(json.dumps({'Version': version, 'SourceCommit': commit,
        'WorkingTreeModified': dirty, 'Files': records}, indent=2) + '\n', encoding='utf-8')
    print(f'{len(records)} files verified; {archive.stat().st_size} bytes; source {commit}; modified={dirty}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    build(parser.parse_args().output.resolve())
