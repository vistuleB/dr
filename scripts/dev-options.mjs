import { parseArgs } from 'node:util';

export function parseDevOptions(args) {
  const { values } = parseArgs({
    args,
    strict: true,
    allowPositionals: false,
    options: {
      course: { type: 'string' },
      host: { type: 'string' },
      port: { type: 'string' },
      help: { type: 'boolean', short: 'h' },
    },
  });
  for (const key of ['course', 'host', 'port']) {
    if (values[key] !== undefined && (!values[key].trim() || values[key].startsWith('--'))) {
      throw new Error(`--${key} requires a nonempty value`);
    }
  }
  if (values.port !== undefined) validatePort(values.port);
  return values;
}

export function validatePort(value) {
  if (!/^\d+$/.test(String(value)) || Number(value) < 1 || Number(value) > 65535) {
    throw new Error('Port must be an integer between 1 and 65535');
  }
  return Number(value);
}

// Explicit CLI values override the shell environment, which overrides .env.
export function applyDevOptions(options, env) {
  for (const key of ['course', 'host', 'port']) {
    if (options[key] !== undefined) env[key.toUpperCase()] = options[key];
  }
}
