# Muse device SDK and an ARCHi cyberdeck

Reviewed 2 October 2026. This is a device-interface proposal, not an installed SDK, paired device or hardware qualification.

The [Muse gadget repository](https://github.com/facebookincubator/muse-gadget-sdk) supplies ESP32 firmware and a Linux endpoint. Its standard pairing flow still uses the hosted Muse service. The Linux [executor](https://github.com/facebookincubator/muse-gadget-sdk/blob/main/linux/src/musegadget/executor.py) includes Bash commands and account-accessible file operations; importing that executor would introduce another action path outside ARCHi's reviewed owners.

A useful first ARCHi cyberdeck is a display and input surface: the selected companion, task status, one chosen node/version and a button that opens an existing native action. ARCHi's local records remain canonical. A device event would need an authenticated device/session, sequence, expiry, expected source revision and observed acknowledgment. It would not create memories, award learning, expose generic shell/file access or become a second profile store. This contract is proposed; no device transport has been implemented in this cleanup.

The [avatar recipe](https://github.com/facebookincubator/muse-gadget-sdk/blob/main/esp32/tools/muse/AVATAR_RECIPE.md) and [desktop simulator](https://github.com/facebookincubator/muse-gadget-sdk/blob/main/esp32/simulator/README.md) are useful references for compact state-driven characters and deterministic display captures. Use original ARCHi/Liminal artwork. Simulator output does not qualify hardware, power, radio or audio behavior.

Source code is principally Apache-2.0 with documented exceptions; Jollybot artwork is excluded. Hosted SDK-token access has separate [personal/non-commercial terms](https://gadgets.muse.ai/sdk-terms), device limits and distribution restrictions. Adapting licensed source and distributing a Muse-connected product are distinct decisions. No license is changed or commercial clearance inferred here.

First implementation gate: a native-owned, read-only display snapshot plus bounded button input, exercised locally before selecting hardware or adding an actuator. This belongs behind the existing native authority and exact-version contracts described in [the owner map](../native-authority-and-lineage.md).
