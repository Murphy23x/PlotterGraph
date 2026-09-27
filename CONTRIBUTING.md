# Contributing

Thanks for your interest in PlotterGraph! Bug reports, new patterns, and example presets are all welcome.

## Reporting bugs and requesting features

Use the [issue templates](https://github.com/Murphy23x/PlotterGraph/issues/new/choose). For bugs, please mention your OS, Processing version, and (if possible) attach the preset JSON that reproduces the problem.

## Making changes

1. Fork the repository and create a branch from `Dev`.
2. Open `GenerativeLineArt/GenerativeLineArt.pde` in the [Processing IDE](https://processing.org/download) (4.x) and make your change.
3. Check that the sketch still runs, and that SVG export and preset save/load still work.
4. Open a pull request against `Dev`. CI builds the sketch and validates the example presets on every pull request.

### Guidelines

- Keep it dependency-free: no extra Processing libraries.
- Match the existing code style (2-space indentation, short comments where the intent isn't obvious).
- **Adding a pattern:** add its name to `PATTERN_NAMES` and add its parameters and generator alongside the existing ones. Existing preset files store parameters by pattern name, so don't rename existing patterns.
- **Adding an example preset:** save it with the `Save preset...` button, give it a descriptive name (not `preset_<timestamp>.json`, which is git-ignored), and put it in `GenerativeLineArt/presets/`.

## License

By contributing, you agree that your contributions are released under the project's [CC0 1.0 Universal](LICENSE) dedication.
