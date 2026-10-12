# Why this is a native utility, not a custom driver

## Direct observations

The tested EDIFIER M60 already appeared as a stereo USB CoreAudio output before this utility existed. IORegistry showed USB VID `0x2d99`, PID `0xa094`, manufacturer `bestechnic`, exact product `EDIFIER M60`. Audio-control and audio-streaming interfaces were serviced by Apple's `AppleUSBAudio` / `usbaudiod` path. The consumer HID interface advertised standard media input usages; this did not establish a vendor command channel for speaker configuration.

Read-only CoreAudio inspection initially found physical stereo integer PCM at 16-bit/48 kHz and a separate virtual stereo float32/48 kHz format. Advertised physical choices covered 16/24-bit at 48/96 kHz, with mixable/non-mixable variants. No 44.1 kHz physical mode was advertised in this snapshot. A later consented interactive check and independent readback confirmed physical 24-bit/48 kHz. See VERIFICATION.md for actual exercised behavior and remaining limits.

A replacement driver would duplicate the already functioning native path and introduce distribution/security requirements without evidence of a driver defect. The utility exposes the existing format and routing controls without inventing hardware capabilities.

## Manual and official software

The [official manual, section 7](https://new-edifier-us-oss.edifier.com/files/20240914/b229ad7e7c35660c4a9c14dda2f8c27a.pdf) lists Windows 11/10/8/7. It does not explicitly state that other operating systems cannot enumerate the device. Its section 8 explicitly says USB/AUX volume synchronization is unsupported and speaker/device volume should be adjusted separately.

[Edifier Online's generic USB support guidance](https://support.edifier-online.com/api/v2/help_center/en-us/articles/4657564529555.json) says: 'For Mac OS X version 10.6.4 and above. No driver is required.' This is generic guidance, not an M60-specific compatibility certification. A generic Windows download was found, but its suitability for this bestechnic device was not established and it was not executed.

The [manufacturer M60 page](https://www.edifier.com/global/p/computer-speakers/m60) describes 24-bit/96 kHz processing and an internal DSP with active crossover and dynamic range control. That marketing description does not prove an end-to-end bit-perfect computer-to-speaker path.

The [official ConneX App Store listing](https://apps.apple.com/us/app/edifier-connex/id6469028132) offers an iPad-designed app on compatible Apple-silicon Macs while marking it not verified for macOS. M60 BLE control through that Mac app was not exercised here. Speaker EQ/input/firmware control is distinct from USB audio streaming and outside this project.

## REA: exact scope and limitations

REA admitted and content-addressed a locally captured M60 USB registry property-list artifact, SHA-256 `eac37d53ce2ecd7cc2f8d33fe3793744ec14de48ed249bedb80d5426fdf900e1`. Its inventory evidence was `ev_54c56ee6eba6149b1a6aa9b7d65a377c8337cb59770a427eb6bf4f87f4f132db`, inspection evidence `ev_66f20dec18a9a146e8813b08ede305c7d977115d4eec3e4eff74cf295bb6e6ec`.

This REA operation verified artifact inventory/hash only. It explicitly did not parse plist semantics or observe USB runtime behavior. Registry interpretation and physical-format discovery came separately from standard plist parsing and real CoreAudio queries. No vendor firmware was obtained or decompiled, no proprietary protocol was reverse-engineered, and no REA finding is presented as proof of acoustic quality. Raw registry captures and local identifiers are excluded from the shared source/archive.

## Quality interpretation

Reported 24-bit USB output can avoid an unnecessary 16-bit output stage when mixing or reducing digital volume, but it does not recover source detail, guarantee audibly better playback, or bypass the speaker's DSP. A 96 kHz output is not automatically better for 44.1/48 kHz material. Match high-rate sources where appropriate; resampling may otherwise occur. Acoustic quality, bit accuracy, DSP behavior and video-call latency remain unmeasured.
