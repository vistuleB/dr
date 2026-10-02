import path from 'node:path';
import fs from 'node:fs';
import { execFile } from 'node:child_process';

export function parseTooltipCommand(command, projectRoot, course) {
  if (typeof command !== 'string' || /[\r\n\0]/.test(command)) return null;
  let match = /^open\s+(.+)$/.exec(command.trim());
  let kind, target, args;
  if (match) {
    kind = 'image';
    target = match[1];
    if (!/\.(png|jpe?g|svg)$/i.test(target)) return null;
  } else {
    match = /^code\s+--goto\s+(.+):(\d+):(\d+)$/.exec(command.trim());
    if (!match) return null;
    kind = 'source';
    target = match[1];
    args = [match[2], match[3]];
  }
  const base = path.resolve(projectRoot, course, kind === 'image' ? 'public' : 'wly');
  target = path.resolve(projectRoot, target);
  const inside = (root, file) => file.startsWith(root + path.sep);
  if (!inside(base, target)) return null;
  // Also disallow symlink escapes when the target already exists.
  if (fs.existsSync(target) && !inside(fs.realpathSync(base), fs.realpathSync(target))) return null;
  return { kind, target, args };
}

export async function launchTooltip(command, { platform = process.platform, execute = execFile, cwd = process.cwd() } = {}) {
  if (command.kind === 'image' && platform !== 'darwin') {
    return { status: 501, success: false, error: `Image tooltip opening is currently supported only on macOS (server platform: ${platform}). Open the image manually in its default application.` };
  }
  if (command.kind === 'source' && platform === 'win32') {
    return { status: 501, success: false, error: 'VS Code tooltip launching on Windows is not yet supported by this server (code.cmd requires a Windows-specific launcher). Open the source manually in VS Code.' };
  }
  const file = command.kind === 'image' ? 'open' : 'code';
  const args = command.kind === 'image' ? [command.target] : ['--goto', `${command.target}:${command.args.join(':')}`];
  return new Promise(resolve => {
    const done = error => {
      if (!error) return resolve({ status: 200, success: true });
      let message = `Could not launch ${file}: ${error.message}`;
      if (file === 'code' && error.code === 'ENOENT') {
        message = platform === 'darwin'
          ? 'VS Code command "code" was not found. In VS Code, open the Command Palette and run "Shell Command: Install code command in PATH", then restart the dev server.'
          : 'VS Code command "code" was not found. Install VS Code and make its code executable available on the server PATH, then restart the dev server.';
      }
      resolve({ status: 500, success: false, error: message });
    };
    try { execute(file, args, { cwd, timeout: 15000 }, done); }
    catch (error) { done(error); }
  });
}
