import { config } from "./config.js";
import { createApp } from "./app.js";
import { createDb } from "./db.js";

const db = createDb();
const app = createApp(db);

app.listen(config.port, "0.0.0.0", () => {
  console.log(`${config.appName} API running on http://localhost:${config.port}`);
});
