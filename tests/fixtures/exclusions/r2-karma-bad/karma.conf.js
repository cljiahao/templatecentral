module.exports = function (config) {
  config.set({ coverageReporter: { exclude: ["src/gen/**"] } });
};
