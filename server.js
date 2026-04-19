const express = require("express");
const http = require("http");
const { Server } = require("socket.io");

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: {
    origin: "*"
  }
});

// 🔥 WICHTIG: Health Check Route
app.get("/", (req, res) => {
  res.send("Server läuft");
});

io.on("connection", (socket) => {
  console.log("User connected");

  socket.on("move", (data) => {
    socket.broadcast.emit("move", data);
  });
});

const PORT = process.env.PORT || 3000;

server.listen(PORT, "0.0.0.0", () => {
  console.log("Server läuft auf Port " + PORT);
});