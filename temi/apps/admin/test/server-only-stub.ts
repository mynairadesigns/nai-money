/**
 * No-op stand-in for the `server-only` package under Vitest.
 *
 * `server-only` exists to make a build fail when a server module is pulled
 * into the client bundle. It resolves through Next's react-server condition,
 * which Vitest does not set — so importing it in a test throws. Aliasing it to
 * this empty module lets pure logic inside server modules stay unit-testable
 * without weakening the real guard in the app build.
 */
export {};
