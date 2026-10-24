"""Original, reproducible piece-contact sounds; no recordings or external samples."""

import math
import random
import struct
import wave
from pathlib import Path

DESTINATION = Path(__file__).resolve().parents[1] / "client-godot/assets/audio/pieces"
SAMPLE_RATE = 44100


def contact(name: str, seed: int, impulse: bool = False) -> None:
    random_source = random.Random(seed)
    duration = 0.045 if impulse else 0.13
    frequencies = (1100, 1830, 2940) if impulse else (310, 730, 1470)
    frequencies = [value * random_source.uniform(0.94, 1.06) for value in frequencies]
    frames = bytearray()
    previous_noise = 0.0
    for index in range(int(SAMPLE_RATE * duration)):
        time = index / SAMPLE_RATE
        noise = random_source.uniform(-1.0, 1.0)
        transient = (noise - previous_noise) * math.exp(-time / 0.006) * 0.17
        previous_noise = noise
        tone = sum(
            math.sin(math.tau * frequency * time)
            * math.exp(-time / (0.012 + harmonic * 0.006))
            / (harmonic + 2)
            for harmonic, frequency in enumerate(frequencies)
        )
        envelope = min(1.0, time / 0.0008) * min(1.0, (duration - time) / 0.008)
        sample = (tone * 0.55 + transient) * envelope * (0.55 if impulse else 1.0)
        frames.extend(struct.pack("<h", round(max(-0.95, min(0.95, sample)) * 32767)))
    with wave.open(str(DESTINATION / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    contact("impulse.wav", 2410, impulse=True)
    for variant in range(3):
        contact(f"landing-{variant + 1}.wav", 2411 + variant)
    print("Four original PCM contact sounds exported to", DESTINATION)


if __name__ == "__main__":
    main()
