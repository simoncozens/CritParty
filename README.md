# Signalling server

Need to start up signalling server before doing anything:

* cd server
* npm install
* node js/server.js

Signalling server runs on port 9000 by default and binds to all IPs.

Signalling server URL is set in CritParty/SignallingClient.m. I'm
running the server on my host.

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
- [ ] Share Glyphs file
- [ ] Receive and open file
- [ ] Share/display path changes
- [ ] Work out what to do when layer changes?
- [ ] Error handling
- [ ] Disconnection
- [ ] Audio/video

# Security

* Source is available for verification
* Only data sent to central server is connection information
* Peer-to-peer channels are encrypted
* Glyphs file passes peer-to-peer to connected host
