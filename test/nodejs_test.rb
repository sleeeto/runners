require 'test_helper'

class NodejsTest < Minitest::Test
  include TestHelper

  INSTALL_OPTION_NONE = Runners::Nodejs::INSTALL_OPTION_NONE
  INSTALL_OPTION_ALL = Runners::Nodejs::INSTALL_OPTION_ALL
  INSTALL_OPTION_PRODUCTION = Runners::Nodejs::INSTALL_OPTION_PRODUCTION
  INSTALL_OPTION_DEVELOPMENT = Runners::Nodejs::INSTALL_OPTION_DEVELOPMENT

  private

  def processor_class
    @processor_class ||= Class.new(Runners::Processor) do
      include Runners::Nodejs

      def analyzer_id; :eslint; end
      def analyzer_bin; "eslint"; end
      def analyzer_name; "ESLint"; end
      def default_analyzer_version; "7.0.0"; end
    end
  end

  def trace_writer
    @trace_writer ||= new_trace_writer
  end

  def actual_commands
    trace_writer.writer.map { |entry| entry[:command_line] }.compact
  end

  def actual_errors
    trace_writer.writer.filter_map { |e| e.fetch(:message) if e[:trace] == :error }
  end

  def actual_messages
    trace_writer.writer.filter_map { |e| e.fetch(:message) if e[:trace] == :message }
  end

  def assert_warnings(expected)
    assert_equal expected, processor.warnings.as_json
  end

  def processor
    @processor
  end

  def new_processor(workspace:)
    @processor = processor_class.new(
      guid: SecureRandom.uuid,
      working_dir: workspace.working_dir,
      config: config,
      shell: Runners::Shell.new(current_dir: workspace.working_dir, trace_writer: trace_writer),
      trace_writer: trace_writer,
    )
  end

  def stub_const(name, value)
    begin
      saved_value = Runners::Nodejs.const_get(name)
      silence_warnings { Runners::Nodejs.const_set(name, value) }
      yield
    ensure
      silence_warnings { Runners::Nodejs.const_set(name, saved_value) }
    end
  end

  def copy(src, dest)
    FileUtils.copy_file src, dest
  end

  def package_version(package_name)
    JSON.parse((processor.working_dir / "node_modules" / package_name / "package.json").read)["version"]
  end

  public

  def test_nodejs_analyzer_local_command
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      assert_equal "node_modules/.bin/eslint", processor.nodejs_analyzer_local_command
    end
  end

  def test_nodejs_analyzer_bin
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      assert_equal "eslint", processor.nodejs_analyzer_bin

      (workspace.working_dir / "node_modules/.bin").mkpath
      (workspace.working_dir / "node_modules/.bin/eslint").write("")
      assert_equal "node_modules/.bin/eslint", processor.nodejs_analyzer_bin
    end
  end

  def test_install_nodejs_deps
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ devDependencies: { "eslint": "5.0.0", "is-string": "1.0.5" } }.to_json)
      constraints = {
        "eslint" => Gem::Requirement.new(">= 5.0.0", "< 7.0.0"),
        "is-string" => Gem::Requirement.new(">= 1.0.0", "< 2.0.0"),
      }

      processor.install_nodejs_deps(constraints: constraints, install_option: INSTALL_OPTION_ALL)

      refute_path_exists processor.package_lock_json_path
      assert_empty processor.warnings
      refute_empty actual_commands
      assert_equal [
        "Installing npm dependencies...",
        "`eslint@5.0.0` was successfully installed.",
      ], actual_messages
      assert_empty actual_errors
      assert_equal "5.0.0", processor.analyzer_version
      assert_equal({ devDependencies: { "eslint": "5.0.0", "is-string": "1.0.5" } }.to_json, processor.package_json_path.read)
    end
  end

  def test_install_nodejs_deps_without_package_json
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      constraints = { "eslint" => Gem::Requirement.new(">= 5.0.0", "< 7.0.0") }

      processor.install_nodejs_deps(constraints: constraints, install_option: INSTALL_OPTION_ALL)

      assert_warnings [{ message: <<~MSG.strip, file: "package.json" }]
        Although `linter.eslint.npm_install` is enabled in your `sider.yml`, `package.json` is missing in your repository.
      MSG
      assert_empty actual_commands
      assert_empty actual_messages
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_option_nil_and_without_package_json
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      constraints = { "eslint" => Gem::Requirement.new(">= 5.0.0", "< 7.0.0") }

      processor.install_nodejs_deps(constraints: constraints, install_option: nil)

      assert_empty processor.warnings
      assert_empty actual_commands
      assert_empty actual_messages
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_option_nil_and_with_package_json
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "is-string": "1.0.5" } }.to_json)
      constraints = { "is-string" => Gem::Requirement.new(">= 1.0.0", "< 2.0.0") }

      processor.install_nodejs_deps(constraints: constraints, install_option: nil)

      assert_path_exists processor.package_json_path
      refute_path_exists processor.package_lock_json_path
      assert_empty processor.warnings
      refute_empty actual_commands
      refute_empty actual_messages
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_option_none_and_without_package_json
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      constraints = { "eslint" => Gem::Requirement.new(">= 5.0.0", "< 7.0.0") }

      processor.install_nodejs_deps(constraints: constraints, install_option: INSTALL_OPTION_NONE)

      refute_path_exists processor.package_json_path
      assert_empty processor.warnings
      assert_empty actual_commands
      assert_empty actual_messages
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_option_none_and_with_package_json
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "eslint": "6.0.0" } }.to_json)
      constraints = { "eslint" => Gem::Requirement.new(">= 5.0.0", "< 7.0.0") }

      processor.install_nodejs_deps(constraints: constraints, install_option: INSTALL_OPTION_NONE)

      assert_path_exists processor.package_json_path
      assert_empty processor.warnings
      assert_empty actual_commands
      assert_empty actual_messages
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_without_deps
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({}.to_json)
      constraints = { "eslint" => Gem::Requirement.new(">= 5.0.0") }

      processor.install_nodejs_deps(constraints: constraints, install_option: INSTALL_OPTION_ALL)

      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
      assert_includes actual_messages, "`eslint` is required but not installed (not in your `package.json`)."
      assert_includes actual_messages, "All constraints are not satisfied. The default version `7.0.0` will be used instead."
      assert_equal "7.0.0", processor.analyzer_version
    end
  end

  def test_install_nodejs_deps_with_missing_deps
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "classcat": "5.0.3" }}.to_json)
      constraints = { "is-string" => Gem::Requirement.new(">= 1.0.0") }

      processor.install_nodejs_deps(constraints: constraints, install_option: INSTALL_OPTION_ALL)

      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
      assert_includes actual_messages, "`is-string` is required but not installed (not in your `package.json`)."
      assert_includes actual_messages, "All constraints are not satisfied. The default version `7.0.0` will be used instead."
      assert_equal "7.0.0", processor.analyzer_version
    end
  end

  def test_install_nodejs_deps_with_unsatisfied_deps
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "classcat": "5.0.3", "is-string": "1.0.5" }}.to_json)
      constraints = {
        "classcat" => Gem::Requirement.new(">= 6.0.0"),
        "is-string" => Gem::Requirement.new(">= 1.0.0"),
      }

      processor.install_nodejs_deps(constraints: constraints, install_option: INSTALL_OPTION_ALL)

      assert_warnings [{ message: <<~MSG.strip, file: "package.json" }]
        Installed `classcat@5.0.3` does not satisfy our constraint `>=6.0.0`. Please update it as possible.
      MSG
      refute_empty actual_commands
      assert_empty actual_errors
      assert_includes actual_messages, "All constraints are not satisfied. The default version `7.0.0` will be used instead."
      assert_equal "7.0.0", processor.analyzer_version
    end
  end

  def test_install_nodejs_deps_with_hook_script
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ scripts: { postinstall: "exit 1" }, dependencies: { "classcat": "5.0.3" } }.to_json)

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_ALL)

      assert_equal "5.0.3", package_version("classcat")
      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_engine_strict
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ engines: { node: "8" }, dependencies: { "classcat": "5.0.3" } }.to_json)
      processor.working_dir.join(".npmrc").write("engine-strict = true")

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_ALL)

      assert_equal "5.0.3", package_version("classcat")
      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_production
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "classcat": "5.0.3" }, devDependencies: { "is-string": "1.0.5" } }.to_json)

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_PRODUCTION)

      assert_equal "5.0.3", package_version("classcat")
      refute_path_exists processor.working_dir / "node_modules" / "is-string"
      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_development
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "classcat": "5.0.3" }, devDependencies: { "is-string": "1.0.5" } }.to_json)

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_DEVELOPMENT)

      assert_equal "5.0.3", package_version("classcat")
      assert_equal "1.0.5", package_version("is-string")
      assert_warnings [{ message: "`development` of `linter.eslint.npm_install` is deprecated. It falls back to `true` instead.", file: "package.json" }]
      refute_empty actual_commands
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_package_lock_json
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "typescript": "^3.5.0" } }.to_json)
      copy data("package-lock.json"), processor.package_lock_json_path

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_ALL)

      assert_equal "3.5.3", package_version("typescript")
      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
      assert_equal data("package-lock.json").read, processor.package_lock_json_path.read
    end
  end

  def test_install_nodejs_deps_with_package_lock_json_production
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "typescript": "^3.5.0" } }.to_json)
      copy data("package-lock.json"), processor.package_lock_json_path

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_PRODUCTION)

      assert_equal "3.5.3", package_version("typescript")
      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_package_lock_json_development
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ devDependencies: { "typescript": "^3.5.0" } }.to_json)
      copy data("package-lock.dev.json"), processor.package_lock_json_path

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_DEVELOPMENT)

      assert_match %r{^3\.\d+\.\d+$}, package_version("typescript")
      assert_warnings [{ message: "`development` of `linter.eslint.npm_install` is deprecated. It falls back to `true` instead.", file: "package.json" }]
      refute_empty actual_commands
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_package_lock_json_v2
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "typescript": "^3.5.0" } }.to_json)
      copy data("package-lock.v2.json"), processor.package_lock_json_path

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_ALL)

      assert_equal "3.9.9", package_version("typescript")
      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
    end
  end

  def test_install_nodejs_deps_with_yarn_lock
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "classcat": "^5.0.0" } }.to_json)
      copy data("yarn.lock"), processor.working_dir.join("yarn.lock")

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_ALL)

      assert_equal "5.0.0", package_version("classcat")
      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
      assert_equal data("yarn.lock").read, processor.working_dir.join("yarn.lock").read
    end
  end

  def test_install_nodejs_deps_with_non_existent_deps
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "foo": "github:sider/foo" } }.to_json)

      error = assert_raises Runners::Nodejs::NpmInstallFailed do
        processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_ALL)
      end

      expected_error_message = <<~MSG.strip
        `npm install` failed. If you want to avoid this installation, try one of the following in your `sider.yml`:

        - Set `false` to `linter.eslint.npm_install`
        - Set necessary packages to `linter.eslint.dependencies`

        See also <https://help.sider.review/getting-started/custom-configuration>
      MSG
      assert_equal [expected_error_message], actual_errors
      assert_equal expected_error_message, error.message
      refute_path_exists processor.working_dir / "node_modules"
    end
  end

  def test_install_nodejs_deps_with_dependencies
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "is-string": "1.0.0", "eslint": "7.0.0" } }.to_json)

      deps_dir = mktmpdir.to_path

      with_stubbed_env({ "RUNNERS_USER_DEPS_DIR" => deps_dir }) do
        processor.install_nodejs_deps(
          constraints: {},
          dependencies: ["classcat", "is-string@1.0.5", { name: "is-nan-x", version: "2.1.0" }],
          install_option: INSTALL_OPTION_ALL,
        )
      end

      installed_versions_output = trace_writer.writer.find { |e| e[:trace] == :stdout && e[:string].include?(deps_dir) }.fetch(:string)
      assert_match %r{classcat@\d+\.\d+\.\d+}, installed_versions_output
      assert_match "is-string@1.0.5", installed_versions_output
      assert_match "is-nan-x@2.1.0", installed_versions_output
      assert_empty processor.warnings
      refute_empty actual_commands
      assert_empty actual_errors
      assert_equal({ dependencies: { "is-string": "1.0.0", "eslint": "7.0.0" } }.to_json, processor.package_json_path.read)
      refute_path_exists processor.package_lock_json_path
      refute_path_exists processor.node_modules_path
    end
  end

  def test_install_nodejs_deps_with_unmet_deps
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      processor.package_json_path.write({ dependencies: { "eslint": "7.21.0", "eslint-config-airbnb": "18.1.0" } }.to_json)

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_ALL)

      assert_equal "7.21.0", package_version("eslint")
      assert_equal "18.1.0", package_version("eslint-config-airbnb")
      assert_empty processor.warnings
    end
  end

  def test_install_nodejs_deps_with_workspaces
    with_workspace do |workspace|
      new_processor(workspace: workspace)

      (processor.working_dir / "packages" / "a").tap do |dir|
        dir.mkpath
        (dir / "package.json").write({ dependencies: { "classcat": "5.0.3" } }.to_json)
      end
      (processor.working_dir / "packages" / "b").tap do |dir|
        dir.mkpath
        (dir / "package.json").write({ dependencies: { "is-string": "1.0.5" } }.to_json)
      end
      processor.package_json_path.write({ workspaces: ["packages/a", "packages/b"] }.to_json)

      processor.install_nodejs_deps(constraints: {}, install_option: INSTALL_OPTION_ALL)

      assert_equal "5.0.3", package_version("classcat")
      assert_equal "1.0.5", package_version("is-string")
      assert_empty processor.warnings
    end
  end
end
