import path from 'node:path';

import { defineConfig } from 'vitest/config';

/**
 * Tests target pure logic — mapping, validation, arithmetic — rather than
 * rendered components, matching the convention used across this repo. Anything
 * that needs Firestore or Firebase Auth belongs in the emulator-backed
 * end-to-end checks documented in apps/admin/README.md instead.
 */
export default defineConfig({
  resolve: {
    alias: {
      '@': path.join(__dirname, 'src'),
      // See test/server-only-stub.ts — the real package only resolves under
      // Next's react-server condition, which Vitest does not set.
      'server-only': path.join(__dirname, 'test', 'server-only-stub.ts'),
    },
  },
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
});
