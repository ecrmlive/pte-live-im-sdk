# Third-party notices

The uni-app x UTS E2EE implementation and the standalone Web SDK package `@pte-live/pte-im-sdk` use the following build-time dependencies. They are pinned to exact versions in `uni_modules/pte-im-sdk/package.json` and `web/pte-im-sdk/package.json`; the SDK does not fetch code at runtime.

| Package | Version | License | Purpose |
| --- | --- | --- | --- |
| `@noble/ciphers` | `2.0.1` | MIT | AES-256-GCM |
| `@noble/curves` | `2.0.1` | MIT | NIST P-256 ECDH |
| `@noble/hashes` | `2.0.1` | MIT | HMAC-SHA-256 |

The host must retain upstream license notices when redistributing a built mini-program, H5, or browser bundle. No cryptographic key, UserSig signing secret, or Tencent COS credential is included in these dependencies.
