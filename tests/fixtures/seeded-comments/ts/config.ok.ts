import a from 'a';
// Loads the second module.
import b from 'b';

// Settings used by the tool.
export default {
  // Where output goes.
  out: 'dist',
  // Which files count.
  include: [a, b],
};

// Runs once at load.
if (a) {
  // Registers the hook.
  register();
}
// Guards the load.
try {
  // Reads the file.
  read();
} catch {
  // Falls back.
  fallback();
}
