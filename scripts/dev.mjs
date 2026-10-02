import { fileURLToPath } from 'node:url';
import { applyDevOptions, parseDevOptions } from './dev-options.mjs';

let server;
try {
  const options = parseDevOptions(process.argv.slice(2));
  if (options.help) {
    console.log(`Usage: npm run dev -- [--course 235A] [--host 127.0.0.1] [--port 3003]

Options override environment variables and .env settings.
npm run dev:mobile -- --course 235B exposes the server on the local network.
Render the course first: gleam run -- --which 235A --local`);
  } else {
    process.chdir(fileURLToPath(new URL('../', import.meta.url)));
    applyDevOptions(options, process.env);
    const { createServer } = await import('vite');
    server = await createServer({ configFile: fileURLToPath(new URL('../vite.config.js', import.meta.url)) });
    await server.listen();
    server.printUrls();
    let closing = false;
    const close = async () => {
      if (closing) return;
      closing = true;
      await server.close();
      process.exit(0);
    };
    process.once('SIGINT', close);
    process.once('SIGTERM', close);
  }
} catch (error) {
  await server?.close();
  console.error(`Dev server: ${error.message}`);
  process.exitCode = 1;
}
