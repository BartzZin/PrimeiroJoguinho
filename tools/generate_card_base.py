"""Generate only the shared card base inside the frozen official Modelador3d image."""

import hashlib
import json
from pathlib import Path

from PIL import Image
from trellis_service.jobs import Settings, create_job, job_path, read_json, run_job

references = Path('/references')
destination = Path('/app/outputs')
manifest_path = destination / 'cards.json'
manifest = read_json(manifest_path)
settings = Settings(resolution='512', seed=42, steps=12, texture_size=1024,
                    decimation_target=20000, preserve_details=False)
failed = []
for path in [references / 'arcane_shield.png']:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    previous = manifest.get(path.stem, {})
    if previous.get('reference_sha256') == digest and (destination / previous.get('model', 'missing')).is_file():
        print('SKIP', path.stem, flush=True)
        continue
    with Image.open(path) as image:
        identifier = create_job(image, settings, source_name=path.name)
    print('START', path.stem, identifier, flush=True)
    stage = None
    for state in run_job(identifier):
        if state['stage'] != stage:
            stage = state['stage']
            print(path.stem, stage, flush=True)
    if state['status'] != 'succeeded':
        failed.append(path.stem)
        print('FAILED', path.stem, state.get('error', state['status']), flush=True)
        continue
    directory = job_path(identifier)
    manifest[path.stem] = {'job_id': identifier, 'model': str(directory.relative_to(destination) / 'model.glb'),
                           'reference_sha256': digest, 'metadata': read_json(directory / 'metadata.json')}
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('DONE', path.stem, flush=True)
raise SystemExit(1 if failed else 0)
