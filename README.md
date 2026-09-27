# BlockDeadLetter

Defensive iOS dylib that forces FomoPeek `apptrace` Bitbucket dead-drop (mailbox) URLs to `https://www.baidu.com`, so the encrypted C2 list is not fetched.

`apptrace` does not expose a patchable mailbox symbol — the URL is obfuscated in `__DATA` and only appears after runtime deobfuscation. This dylib rewrites that plaintext at the `NSString` boundary and chokes `NSURLConnection sendSynchronousRequest` (the send path apptrace uses).

## Build

- Local (macOS + Xcode): `cd deadletter_block && ./build.sh`
- CI: push to GitHub; download the **BlockDeadLetter-dylib** artifact from Actions.

## Inject

1. Copy `BlockDeadLetter.dylib` into `FomoPeek.app/Frameworks/`
2. `insert_dylib '@rpath/BlockDeadLetter.dylib' FomoPeek.app/FomoPeek`
3. Re-sign and install

This repository only tracks the hook sources and CI — not the malware app payload.
