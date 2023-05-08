REBOL [
    Title: "Matrix scheme"
    Type:    module
	Name:    matrix
	Date:    08-May-2023
	Version: 0.2.0
	Author:  @Oldes
	Home:    https://github.com/Oldes/Rebol-Matrix
	Rights:  http://opensource.org/licenses/Apache-2.0
    Purpose: {Possibility to write a chat bot on a Matrix protocol}
    Reference: https://spec.matrix.org/v1.5/client-server-api/
    Needs:   [json]
]


;system/options/log/http: 0  ;; turn off all HTTP traces
;system/options/log/matrix: 1 ;; basic matrix traces
sys/log/info 'MATRIX "Initialize matrix scheme."

sys/make-scheme [
    title: "Matrix Instant Messaging scheme"
    name: 'matrix
    actor: [
        open: func [port [port!] /local state spec host][
            spec: port/spec
            host: copy any [ select spec 'homeserver  https://matrix.org/ ]
            unless url? host [host: join https:// host]
            if slash <> last host [append host slash]
            append host any [ select spec 'client  %_matrix/client/v3/ ]
            if slash <> last host [append host slash]
            
            ;; keep optionaly provided specification in port's state
            set state: construct [
                homeserver:
                token:
                header:
                user-id:
                room-id:
                room-ids:
                user-ids:
                timestamp:
                next-batch:
                user-name:
                rooms:      ;; holds information about joined rooms collected by calls to sync
                callbacks?:
            ] spec

            state/homeserver: host

            ;; if token is not provided, a value stored in user's persistent data is used
            ;; to store this value....
            ;; 1. first set a user using: set-user @name  (or set-user/n for a new user)
            ;; 2. store the value using:  put system/user/data 'matrix-token "..."
            ;; 3. save the data using:    update system/user/data
            state/token: any [state/token user's matrix-token]

            state/room-ids: any [state/room-ids #()]
            state/user-ids: any [state/user-ids #()]
            state/rooms:    #()
            state/timestamp: any [state/timestamp 0]
            state/callbacks?: any [state/callbacks? true]
 
            ;; do not keep initial specs.. just the normalised ref
            port/spec: make system/standard/port-spec-head [
                title: spec/title
                scheme: 'matrix
                ref: rejoin [matrix:// any [select host 'host "matrix.org"]]
            ]
            port/state: state

            if function? select spec 'on-message [port/actor/on-message: :spec/on-message]
            if function? select spec 'on-room-event [port/actor/on-room-event: :spec/on-room-event]


            ;; if user-id is not directly provided, resolve it from the access token
            unless state/user-id [ pick port 'whoami ]
            port
        ]
        write: func[port data /local room user value][
            room: port/state/room-id
            parse data [any [
                [
                    'room set room [ref! | string! | lit-word! | word!] 
                    |     set room  ref!
                ] (
                    ;; Set the current room for use with other commands
                	room: poke port 'room :room
                )
                | [
                    'send copy value some string!
                    |     copy value some string!
                ] (
                    ;; Send one or more plain text messages to the current room
                    forall value [send-message port value/1]
                )
                | 'marker set room string! set value string! (
                    ;; Sets the position of the read marker for a given room,
                    ;; and optionally the read receipt’s location.
                    ;; (only room-id is expected!)
                    send-read-markers port room value
                )
                | 'invite set user [ref! | string!] set value opt string! (
                    ;; This API invites a user to participate in a particular room. They do not start
                    ;; participating in the room until they actually join the room.
                    ;;
                    ;; Only users currently in a particular room can invite other users to join that room.
                    send-invite port :user :value
                )
                | 'join set room [ref! | string! | lit-word! | word!] set value opt string! (
                    ;; This API starts a user participating in a particular room, if that user is
                    ;; allowed to participate in that room. After this call, the client is allowed to
                    ;; see all current state events in the room, and all subsequent events associated
                    ;; with the room until the user leaves the room.
                    room: poke port 'room :room
                    POST port [%join/ room] [reason: any [value ""]]
                )
                | 'leave set room [ref! | string! | lit-word! | word!] set value opt string! (
                    ;; This API stops a user participating in a particular room.
                    ;; 
                    ;; If the user was already in the room, they will no longer be able to see new
                    ;; events in the room. If the room requires an invite to join, they will need to
                    ;; be re-invited before they can re-join.
                    ;; 
                    ;; If the user was invited to the room, but had not joined, this call serves to
                    ;; reject the invite.
                    ;; 
                    ;; The user will still be allowed to retrieve history from the room which they
                    ;; were previously allowed to see.
                    also
                        POST port [%rooms/ get-id port/state/room-ids :room %/leave] [reason: any [value ""]]
                        port/state/room-id: room: none
                )
                | 'forget set room [ref! | string! | lit-word! | word!] (
                    ;; This API stops a user remembering about a particular room.
                    ;; 
                    ;; In general, history is a first class citizen in Matrix. After this API is called,
                    ;; however, a user will no longer be able to retrieve history for this room. If all
                    ;; users on a homeserver forget a room, the room is eligible for deletion from that homeserver.
                    ;; 
                    ;; If the user is currently joined to the room, they must leave the room before calling this API.
                    also 
                        POST port [%rooms/ get-id port/state/room-ids :room %/forget]
                        port/state/room-id: room: none
                )
                | 'kick set user string! set value opt string! (
                    ;; Kick a user from the room.
                    ;;
                    ;; The caller must have the required power level in order to perform this operation.
                    membership/set port room :user 'leave :value
                )
                | 'ban set user string! set value opt string! (
                    ;; A user may decide to ban another user in a room. ‘Banning’ forces the target
                    ;; user to leave the room and prevents them from re-joining the room. A banned
                    ;; user will not be treated as a joined user, and so will not be able to send or
                    ;; receive events in the room. In order to ban someone, the user performing the
                    ;; ban MUST have the required power level.
                    membership/set port room :user 'ban :value
                )
                | 'unban set user string! set value opt string! (
                    ;; Unban a user from the room. This allows them to be invited to the room,
                    ;; and join if they would otherwise be allowed to join according to its join rules.
                    ;;
                    ;; The caller must have the required power level in order to perform this operation.
                    POST port [%rooms/ room %/unban][
                        user_id: get-id port/state/user-ids :user
                        reason: any [value ""]
                    ]
                )
                | skip ;; error?
            ]]
        ]
        pick:
        select: func[port key /local room][
            attempt [
            switch key [
                whoami       [
                    port/state/user-id:
                    select GET port %account/whoami 'user_id
                ]
                displayname  [
                    port/state/user-name:
                    select GET port [%profile/ port/state/user-id %/displayname] 'displayname
                ]
                avatar [
                    as url! select GET port [%profile/ port/state/user-id %/avatar_url] 'avatar_url
                ]
                room [
                    port/state/room-id ;; current room used in commands
                ]
                room-state [
                    GET port [%rooms/ port/state/room-id %/state/ key]
                ]
                joined-rooms [
                    select GET port %joined_rooms 'joined_rooms
                ]
                membership [
                    membership port none none
                ]
            ]]
        ]
        put:
        poke: func[port key value][
            switch key [
                displayname  [
                    PUT port [%profile/ port/state/user-id %/displayname] [displayname: :value]
                ]
                room [
                    port/state/room-id: get-id port/state/room-ids :value
                ]
            ]
        ]
        update: func[port /local data][
            data: GET port either port/state/next-batch [
                append copy %sync?since= port/state/next-batch
            ][              %sync]
            if port/state/callbacks? [process port data]
            port/state/next-batch: data/next_batch
            data
        ]

        on-message: func[port event][]
        on-room-event: func[port room event /local value key membership][
            value: switch event/type [
                "m.room.message"         [
                    port/actor/on-message port event
                    event/content/body
                ]
                "m.room.member"          [
                    key: event/state_key
                    switch membership: event/content/membership [
                        "join"  [ room/memebers/:key: event/content/displayname ]
                        "leave" [ remove/key room/memebers :key ]
                    ]
                    sys/log/more 'MATRIX [as-yellow event/type membership as-green key]
                    return event
                ]
                "m.room.topic"           [room/topic:        event/content/topic]
                "m.room.name"            [room/name:         event/content/name]
                "m.room.avatar"          [room/avatar:       event/content/url]
                "m.room.canonical_alias" [room/alias:        event/content/alias]
                "m.room.guest_access"    [room/guest_access: event/content/guest_access]
                "m.room.join_rules"      [room/join_rules:   event/content/join_rules]
                ;"m.room.history_visibility"
                ;"m.room.create"
                ;"m.room.power_levels"
                ;"m.space.parent"
            ]
            either value [
                sys/log/more  'MATRIX [as-yellow event/type as-green value]
            ][
                sys/log/debug 'MATRIX [as-yellow event/type "ignored"]
            ]
            event
        ]
    ]

    request: func[port method path data /local ctx res][
        ctx: port/state
        if block? path [path: rejoin path]
        unless string? data [
            if block? data [data: make object! data] ;; required for correct JSON result
            data: encode 'json data
        ]
        unless ctx/header [
        	;; reusing the same header
            ctx/header: compose [
                Content-Type:  "application/json"
                Authorization: (join "Bearer " ctx/token)
            ]
        ]
        res: write/all rejoin [ctx/homeserver path] reduce [method ctx/header data]
        data: decode 'json res/3
        if any [res/1 >= 300 res/1 < 200] [
            sys/log/error 'MATRIX data/error
        ]
        data
    ]

    POST: func[port path data][ request port 'POST path data ]
    PUT:  func[port path data][ request port 'PUT  path data ]
    GET:  func[port path     ][ request port 'GET  path none ]

    send-message: func[port message /local room][
        unless room: port/state/room-id [ log-error 'no-room-to-send exit ]        
        PUT port rejoin [%rooms/ room %/send/m.room.message/ transaction-id] [
            msgtype:  "m.text"
            body: message
        ]
    ]
    send-invite: func[port user message][
        unless room: port/state/room-id [ log-error 'no-room-to-invite exit ]
        POST port rejoin [%rooms/ room %/invite] [
            user_id: any [port/state/user-ids/:user user]
            reason:  any [message ""]
        ]
    ]
    send-read-markers: func[port room event][
        ;; Sets the position of the read marker for a given room,
        ;; and optionally the read receipt’s location.
        POST port [%rooms/ room %/read_markers] [
            ;m.fully_read: id ;; deprecated since v1.4
            m.read:
            m.read.private: event
        ]
    ]

    membership: func[port room user /set state message][
        room: any [get-id port/state/room-ids room  port/state/room-id]
        user: any [get-id port/state/user-ids user  port/state/user-id]
        unless room  [ log-error 'no-room exit ]
        unless user  [ log-error 'no-user exit ]
        either state [
            PUT port [%rooms/ room %/state/m.room.member/ user] [
                membership: state
                reason: any [message ""]
            ]
        ][
            GET port [%rooms/ room %/state/m.room.member/ user]
        ]
    ]

    process: func[port data /local ts ts-max ts-prev id prev-room][
        if any [none? data/rooms none? data/rooms/join][return none]
        prev-room: port/state/room-id
        ts-prev: ts-max: port/state/timestamp
        ts: 0
        foreach [room-id data] data/rooms/join [
            port/state/room-id: room-id
            id: none
            info: select port/state/rooms :room-id
            unless info [
                port/state/rooms/:room-id: info: to map! make object! [
                    name: topic: avatar: none
                    memebers: make map! 8
                ]
            ]
            if function? :port/actor/on-room-event [
                foreach e data/state/events [ port/actor/on-room-event port info e ]
            ]

            sys/log/info 'MATRIX ["Processing messages in room:" as-green room-id "(" info/name ")"]
            foreach e data/timeline/events [
                ts: e/origin_server_ts
                id: e/event_id
                ;; evaluate event callbacks only if it is newer than already processed
                if ts > ts-prev [ port/actor/on-room-event port info e ]
            ]
            if id [ send-read-markers port room-id id ]
            ts-max: max ts ts-max
        ]
        ;?? port/state/rooms
        port/state/room-id: prev-room
        port/state/timestamp: ts-max
    ]

;    precise-timestamp: func[/local n s][
;        n: now/precise
;        s: n/time/second
;        s: to integer! (1000 * (s - to integer! s))
;        ajoin [1000 * to integer! n s]
;    ]

    transaction-id: does [
        ++ counter
        ajoin [to integer! now #"_" counter]
    ]

    log-error: func[id][ sys/log/error 'MATRIX any [select errors id form id] ]
    errors: #(
        no-room:           "Missing room!"
        no-user:           "Missing user!"
        no-room-to-send:   "Failed to send a message, because no room is specified!"
        no-room-to-invite: "Failed to send an invite, because no room is specified!"
    )
    counter: 0

    get-id: func[ids value][
		any [
            select ids :value
            attempt [select ids to word! :value]
            :value
        ]
    ]
]
