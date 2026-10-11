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
};

export default nextConfig;