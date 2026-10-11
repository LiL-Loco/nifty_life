import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // mysql2 is a native module and must stay on the Node runtime. Every page in
  // this app is a server component or a server action, so nothing should ever
  // try to bundle it into a browser bundle.
  serverExternalPackages: ['mysql2'],
  poweredByHeader: false,
};

export default nextConfig;