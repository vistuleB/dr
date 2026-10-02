import fs from 'node:fs';
import path from 'node:path';

export const sharedAssets = ['app.css', 'local.css', 'app.js', 'mathjax_setup.js', 'tex-svg.js'];
export function checkCourse(projectRoot, course) {
  const publicRoot = path.resolve(projectRoot, course, 'public');
  const errors = [];
  if (!fs.existsSync(path.join(publicRoot, 'index.html'))) {
    errors.push(`Missing ${course}/public/index.html. Generate HTML first: gleam run -- --which ${JSON.stringify(course)} --local`);
  }
  for (const asset of sharedAssets) {
    const target = path.join(publicRoot, asset);
    const remedy = `Restore ${course}/public/${asset} as a symlink to ../../shared/${asset}. On Windows, enable Developer Mode and Git core.symlinks before checking out links; alternatively copy shared/${asset} here and keep the copy synchronized.`;
    try {
      const stat = fs.lstatSync(target);
      if (stat.isSymbolicLink()) {
        if (fs.realpathSync(target) !== fs.realpathSync(path.join(projectRoot, 'shared', asset))) {
          errors.push(`Wrong shared-asset link: ${target}. ${remedy}`);
        }
      } else if (!stat.isFile()) {
        errors.push(`Shared asset is not a file: ${target}. ${remedy}`);
      } else if (stat.size < 1024 && /^\.\.\/\.\.\/shared\//.test(fs.readFileSync(target, 'utf8').trim().replaceAll('\\', '/'))) {
        errors.push(`Symlink checked out as a text file: ${target}. ${remedy}`);
      }
    } catch {
      errors.push(`Missing or broken shared asset: ${target}. ${remedy}`);
    }
  }
  if (errors.length) throw new Error(errors.join('\n'));
}
