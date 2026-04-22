import { defineConfig, loadEnv } from "vite";
import fs from "node:fs";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");

  // disallow any param after `npm run dev`
  const args = process.argv.slice(4); // anything beyond `node vite --config vite.config.js`
  if (args.length !== 0) {
    console.error(
      `\n\x1b[41m\x1b[37m ERROR \x1b[0m Unknown command: '${args[0]}'. Please put '.env' arguments as prefixes to 'npm run'.`,
    );
    process.exit(1);
  }

  const courseFolder = env.COURSE || env.COURSE || "235A";
  const rootPath = `${courseFolder}/public`;
  const serverPort = Number(env.PORT || env.PORT) || 3003;

  // --- validate existence of a course ---
  if (!fs.existsSync(courseFolder)) {
    // check if the base directory even exists
    console.error(
      `\n\x1b[41m\x1b[37m ERROR \x1b[0m Course directory '\x1b[33m${courseFolder}\x1b[0m' not found.`,
    );
    process.exit(1);
  } else if (!fs.existsSync(rootPath)) {
    // base directory exists, but /public is missing
    console.error(
      `\n\x1b[41m\x1b[37m ERROR \x1b[0m Course directory '\x1b[33m${courseFolder}\x1b[0m' does not have a '\x1b[33mpublic/\x1b[0m' folder.`,
    );
    process.exit(1);
  }

  return {
    root: rootPath,
    plugins: [
      {
        name: "server-log-customizer",
        configureServer(server) {
          const _print = server.printUrls;
          server.printUrls = () => {
            console.log(
              `  \x1b[32m➜\x1b[0m  \x1b[1mServing:\x1b[0m \x1b[36m${rootPath}\x1b[0m`,
            );
            _print();
          };
        },
      },
    ],
    server: {
      port: serverPort,
      host: "127.0.0.1",
      cors: {
        origin: ["http://localhost:*", "http://127.0.0.1:*"],
      },
    },
  };
});
