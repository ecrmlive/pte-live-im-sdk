# Third-party notices

The uni-app x UTS E2EE implementation uses the following build-time dependencies. They are pinned to exact versions in `uni_modules/pte-live-im/package.json`; the SDK does not fetch code at runtime.

| Package | Version | License | Purpose |
| --- | --- | --- | --- |
| `@noble/ciphers` | `2.0.1` | MIT | AES-256-GCM |
| `@noble/curves` | `2.0.1` | MIT | NIST P-256 ECDH |
| `@noble/hashes` | `2.0.1` | MIT | HMAC-SHA-256 |

The host must retain upstream license notices when redistributing a built mini-program or H5 bundle. No cryptographic key, UserSig signing secret, or Tencent COS credential is included in these dependencies.
