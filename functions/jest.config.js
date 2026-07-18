/**
 * Jest configuration for Cloud Functions tests.
 *
 * Runs in CommonJS mode (package.json has no "type":"module", so emit is CJS).
 * ts-jest compiles TypeScript against tsconfig.test.json. The moduleNameMapper
 * strips the ".js" extensions the source uses for NodeNext relative imports so
 * ts-jest resolves them back to the ".ts" sources.
 *
 * Tests run against the Firestore emulator (started by `firebase emulators:exec`
 * in the "test" npm script). FIRESTORE_EMULATOR_HOST is injected by that script.
 */
module.exports = {
  testEnvironment: "node",
  testMatch: ["**/__tests__/**/*.test.ts"],
  moduleFileExtensions: ["ts", "js", "json", "node"],
  moduleNameMapper: {
    "^(\\.{1,2}/.*)\\.js$": "$1",
  },
  transform: {
    "^.+\\.ts$": ["ts-jest", {tsconfig: "<rootDir>/tsconfig.test.json"}],
  },
  setupFiles: ["<rootDir>/src/__tests__/setup.ts"],
  testTimeout: 30000,
};
