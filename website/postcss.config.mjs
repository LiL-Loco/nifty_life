/**
 * PostCSS. One plugin: Tailwind v4.
 *
 * v4 needs no tailwind.config.js — the theme lives in `globals.css` under
 * `@theme`, which is why there is no config file in this project. The plugin
 * package is `@tailwindcss/postcss`, NOT `tailwindcss` itself; naming the wrong
 * one fails with a message that talks about a missing `tailwind.config.js`.
 */
export default {
  plugins: {
    '@tailwindcss/postcss': {},
  },
};