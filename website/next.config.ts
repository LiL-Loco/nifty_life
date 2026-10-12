import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // mysql2 is a native module and must stay on the Node runtime. Every page in
  // this app is a server component or a server action, so nothing should ever
  // try to bundle it into a browser bundle.
  serverExternalPackages: ['mysql2'],
  poweredByHeader: false,

  // The Docker image copies `.next/standalone`, which only exists because of
  // this. Without it the image would ship node_modules and a second copy of
  // every dependency. `next start` still works locally — standalone is an
  // additional output, not a replacement.
  output: 'standalone',

  // OFF by default, and the default is the point.
  //
  // `next build` type-checks with `tsc` after compiling, and on a small host
  // that step is the memory peak — it died twice in a row, silently, because
  // the kernel kills the process and Coolify truncates the line that would have
  // said so. Compiling itself now succeeds.
  //
  // Set SKIP_TYPECHECK=1 to trade that check away for a deploy on a box that
  // cannot hold it. `npm run typecheck` is the real gate and should be run
  // before pushing, not instead of here: this only moves where the check
  // happens, and a build that skips it will happily ship a type error.
  typescript: { ignoreBuildErrors: process.env.SKIP_TYPECHECK === '1' },
};

export default nextConfig;