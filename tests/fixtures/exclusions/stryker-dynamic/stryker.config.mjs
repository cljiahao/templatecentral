const skip = ['!src/a/**'];
export default {
  mutate: ['src/**/*.ts', ...skip],
};
