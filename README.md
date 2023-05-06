[![Gitter](https://badges.gitter.im/rebol3/community.svg)](https://app.gitter.im/#/room/#Rebol3:gitter.im)
[![Zulip](https://img.shields.io/badge/zulip-join_chat-brightgreen.svg)](https://rebol.zulipchat.com/)

# Rebol/Matrix

[Matrix Instant Messaging](https://matrix.org/) scheme for [Rebol3](https://github.com/Oldes/Rebol3)

## Usage

This is just an initial implementation so far, but the basic use is:

```rebol
import %path/to/matrix.reb
;; or if installed in module's directory just:
;import 'matrix


;; initialize a client's context:
bot: open [scheme: 'matrix token: "YOUR-MATRIX-ACCESS-TOKEN"]

;; join some room using a room id:
write bot [join "!LxIlYCUAqqzszxUrPA:matrix.org"]

;; list joined rooms:
pick bot 'joined-rooms
;== ["!LxIlYCUAqqzszxUrPA:matrix.org" "!BifvPgwpwksfzMeZoh:gitter.im" "!tSZtAQLOQBHwBTWPop:gitter.im"]

;; send a message to a room using its id:
write bot [room "!LxIlYCUAqqzszxUrPA:matrix.org" send "Hello!"]

;; once the room is set, it is possible to send messages using just:
write bot ["Is anybody out there?" "I am so lonely!"]
```
