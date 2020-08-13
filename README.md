# Signalling server

Signalling server URL is set in `CritParty/SignallingClient.m`.
I'm running the server on my host. I'm also running a STUN server 
there too.

# To use

As host:

Edit > CritParty. In "Share" pane, add username and make up password.
Hit connect and you get a session ID.

As Guest:

Open "Join" pane, add username and give same password, paste in session
ID.

# Current state and todo

- [x] Establish connection
- [x] Share mouse events
- [x] Display mouse events
- [x] Share Glyphs file
- [x] Receive and open file
- [x] Share/display path changes
- [x] Work out what to do when layer changes?
- [x] Error handling
- [x] Disconnection
- [ ] Audio/video

# Security

* Source is available for verification
* Only data sent to central server is connection information
* Peer-to-peer channels are encrypted
* Glyphs file passes peer-to-peer to connected host
