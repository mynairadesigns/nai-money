import js from '@eslint/js';
// eslint-config-next v16 ships a flat-config ARRAY as its default export,
// not a factory — spread it, don't call it.
import next from 'eslint-config-next';
import tseslint from 'typescript-eslint';

export default [
  { ignores: ['.next/', 'node_modules/', 'next-env.d.ts'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...next,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { console: 'readonly', process: 'readonly' },
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },
];
