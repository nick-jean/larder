// Local demo: in-memory MongoDB + dev auth ("Authorization: Bearer dev:<uid>").
import { spawn } from "node:child_process";
import { MongoMemoryServer } from "mongodb-memory-server";

const port = process.env.PORT ?? "3000";
const mongod = await MongoMemoryServer.create();
const env = { ...process.env, MONGODB_URI: mongod.getUri(), AUTH_DEV_BYPASS: "1", PORT: port };
const next = spawn("pnpm", ["exec", "next", "dev", "-p", port], { env, stdio: "inherit" });
const stop = async () => {
  next.kill();
  await mongod.stop();
  process.exit(0);
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
console.log(`\nLarder API demo on http://localhost:${port} (MongoDB in memory, dev auth on).\n`);
