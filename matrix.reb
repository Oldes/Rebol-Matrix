REBOL [
    Title: "Matrix scheme"
    Type:    module
	Name:    matrix
	Date:    06-May-2023
	Version: 0.1.0
	Author:  @Oldes
	Home:    https://github.com/Oldes/Rebol-Matrix
	Rights:  http://opensource.org/licenses/Apache-2.0
    Purpose: {Possibility to write a chat bot on a Matrix protocol}
    Reference: https://spec.matrix.org/v1.5/client-server-api/
    Needs:   [json]
]


;system/options/log/http: 0  ;; turn off all HTTP traces
system/options/log/matrix: 1 ;; basic matrix traces
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
 
            ;; do not keep initial specs.. just the normalised ref
            port/spec: make system/standard/port-spec-head [
                title: spec/title
                scheme: 'matrix
                ref: rejoin [matrix:// any [select host 'host "matrix.org"]]
            ]
            port/state: state
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
                	room: poke port 'room :room
                )
                | [
                    'send copy value some string!
                    |     copy value some string!
                ] (
                    forall value [send-message port value/1]
                )
                | 'invite set user [ref! | string!] set value opt string! (
                    send-invite port :user :value
                )
                | 'join set room [ref! | string! | lit-word! | word!] set value opt string! (
                    room: poke port 'room :room
                    POST port [%join/ room] object [reason: any [value ""]]
                )
                | 'leave set room [ref! | string! | lit-word! | word!] set value opt string! (
                    room: poke port 'room :room
                    POST port [%rooms/ room %/leave] object [reason: any [value ""]]
                )
                | 'kick set user string! set value opt string! (
                    membership/set port room :user 'leave :value
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
                    PUT port [%profile/ port/state/user-id %/displayname] object [displayname: :value]
                ]
                room [
                    port/state/room-id: any [
                        select port/state/room-ids :value
                        attempt [select port/state/room-ids to word! :value]
                        :value
                    ]
                ]
            ]
        ]
        update: func[port /local data][
            data: GET port either port/state/next-batch [
                append copy %sync?since= next-batch
            ][              %sync]
            port/state/next-batch: data/next_batch
            data
        ]
    ]

    request: func[port method path data /local ctx res][
        ctx: port/state
        if block? path [path: rejoin path]
        unless string? data [data: encode 'json data]
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
        PUT port rejoin [%rooms/ room %/send/m.room.message/ transaction-id] object [
            msgtype:  "m.text"
            body: message
        ]
    ]
    send-invite: func[port user message][
        unless room: port/state/room-id [ log-error 'no-room-to-invite exit ]
        POST port rejoin [%rooms/ room %/invite] object [
            user_id: any [port/state/user-ids/:user user]
            reason:  any [message ""]
        ]
    ]

    membership: func[port room user /set state message][
        room: any [room port/state/room-id]
        user: any [user port/state/user-id]
        unless room: port/state/room-id [ log-error 'no-room exit ]
        either state [
            PUT port [%rooms/ room %/state/m.room.member/ user] object [
                membership: state
                reason: any [message ""]
            ]
        ][
            GET port [%rooms/ room %/state/m.room.member/ user]
        ]
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
        no-room-to-send:   "Failed to send a message, because no room is specified!"
        no-room-to-invite: "Failed to send an invite, because no room is specified!"
    )
    counter: 0
]