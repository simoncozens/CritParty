import * as express from 'express';
import * as WebSocket from 'ws';
import * as http from 'http';
import { v4 as uuid } from 'uuid';
import { ExpiringCache } from './expiringcache';

const app = express();

var server = http.createServer(app);

const port = process.env.PORT || 9000;

const wss = new WebSocket.Server({ server: server });

interface Connection {
	socket: any;
	username: string;
	peerId: string;
	session: Session;
}
interface Session {
	sessionId: string;
	host: Connection;
	guests: Connection[];
	password: string;
}

var sessions = new ExpiringCache<Session>();

function getNewSessionID(): string {
	var id = 0;
	var min = 100000000;
	var max = 999999999;
	while (!id || sessions.get(id.toString())) {
		id = Math.floor(Math.random() * (max - min + 1)) + min;
	}
	sessions[id.toString()] = {} as Session; // Tiny chance of race
	return id.toString();
}

function sendTo(connection: Connection, message: object) {
	console.log("Sending to %s/%s: %s", connection.username, (connection.session && connection.session.sessionId), message)
	connection.socket.send(JSON.stringify(message));
}

function sendError(connection: Connection, message: string) {
	console.log("Sending error to %s/%s: %s", connection.username, (connection.session && connection.session.sessionId), message)
	connection.socket.send(JSON.stringify({ "error": message, "ok": false }));
}

function checkPassword(message: object): boolean {
	return message["password"] && message["password"].length > 5;
}

function findUser(connection: Connection, peerid: string): Connection | undefined {
	var c = connection.session.guests.find(c => c.peerId == peerid);
	return c;
}

wss.on("connection", function(ws) {
	var connection: Connection = {
		socket: ws,
		peerId: uuid(),
		session: null,
		username: null
	};
	console.log(`Got connection from peer ${connection.peerId}`)

	ws.on("message", msg => {
		let data: object;
		try { data = JSON.parse(msg.toString()); }
		catch (e) {
			console.log("Invalid JSON");
			data = {};
			return;
		}
		console.log(`Got message ${JSON.stringify(msg)} from peer ${connection.peerId}`)
		if (data["type"] == "newsession") {
			if (!checkPassword(data)) { return sendError(connection, "Password not long enough"); }
			if (!data["username"]) { return sendError(connection, "No username"); }

			var session: Session = {
				host: connection,
				sessionId: getNewSessionID(),
				guests: [],
				password: data["password"]
			}
			connection.username = data["username"];
			connection.session = session;
			sessions.put(session.sessionId, session);
			sendTo(connection, { "sessionid": session.sessionId });
			console.log("");
			return;
		}

		if (data["type"] == "joinsession") {
			if (!data["username"]) { return sendError(connection, "No username"); }
			let password = data["password"];
			let sessionId = data["sessionid"];
			if (!sessionId) { return sendError(connection, "no session id"); }
			let username = data["username"];
			let offer = data["offer"];
			if (!offer) { return sendError(connection, "What're you offering?") }
			sessionId = sessionId.replace(/\D+/g, "")
			var session = sessions.get(sessionId);
			if (!session || password != session.password) {
				return sendError(connection, "Session unknown or wrong password")
			}
			if (session.guests.some((x) => x.username == username)) {
				return sendError(connection, "Username already taken")
			}
			connection.session = session;
			connection.username = username;
			session.guests.push(connection);
			sendTo(connection, { "ok": true })
			sendTo(session.host, { "type": "newconnection", "username": username, "peerid": connection.peerId, "offer": offer })
			console.log("");
			return;
		}

		if (data["type"] == "answer") {
			// Host answers to guest offer
			if (!connection.session) {
				return sendError(connection, "You're not answering anyone!")
			}
			if (!data["peerid"]) {
				return sendError(connection, "I don't know who you're replying to")
			}
			// Find peer in session guests
			let peerconnection = findUser(connection, data["peerid"]);
			if (!peerconnection) {
				return sendError(connection, "I couldn't find that user")
			}
			sendTo(peerconnection, data);
			console.log("");
			return;
		}
		if (data["type"] == "ice-candidate") {
			// Now these things go both ways
			if (!connection.session) {
				return sendError(connection, "You're not in a session!")
			}
			// Message came from guest
			if (connection != connection.session.host) {
				data["peerid"] = connection.peerId;
				sendTo(connection.session.host, data)
				console.log("");
				return;
			}
			// Message came from host
			if (!data["peerid"]) {
				return sendError(connection, "I don't know who you're replying to")
			}
			// Find peer in session guests
			let peerconnection = findUser(connection, data["peerid"]);
			if (!peerconnection) {
				return sendError(connection, "I couldn't find that user")
			}
			sendTo(peerconnection, data);
			console.log("");
			return;
		} else {
			sendError(connection, "Unknown message")
			console.log("");
		}
	});
})

console.log("Listening")
server.listen(port);
