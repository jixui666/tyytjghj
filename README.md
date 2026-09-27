# BlockDeadLetter

Defensive iOS dylib that rewrites FomoPeek `apptrace` Bitbucket dead-drop URLs to `https://www.baidu.com`, so the encrypted C2 list is not fetched.

## Build

- Local (macOS + Xcode): `cd deadletter_block && ./build.sh`
- CI: push to GitHub; download the **BlockDeadLetter-dylib** artifact from Actions.

## Inject

1. Copy `BlockDeadLetter.dylib` into `FomoPeek.app/Frameworks/`
2. `insert_dylib '@rpath/BlockDeadLetter.dylib' FomoPeek.app/FomoPeek`
3. Re-sign and install

This repository only tracks the hook sources and CI — not the malware app payload.
