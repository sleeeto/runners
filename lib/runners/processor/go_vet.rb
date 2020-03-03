module Runners
  class Processor::GoVet < Processor
    include Go

    Schema = StrongJSON.new do
      let :runner_config, Schema::BaseConfig.base
    end

    register_config_schema(name: :go_vet, schema: Schema.runner_config)

    def self.ci_config_section_name
      # Section name in sideci.yml, Generally it is the name of analyzer tool.
      "go_vet"
    end

    def analyzer_bin
      "gometalinter"
    end

    def analyzer_name
      "go_vet"
    end

    def setup
      add_warning_for_deprecated_linter(alternative: "GolangCi-Lint",
                                        ref: "https://help.sider.review/tools/go/govet",
                                        deadline: Time.new(2020, 4, 30))
      yield
    end

    def analyze(changes)
      # NOTE: go_vet cannot output with JSON format, so we use Gometalinter.
      stdout, _, _ = capture3(
        analyzer_bin,
        '--disable-all',
        '--enable=vet',
        '--enable-gc',
        '--json',
        './...',
        '--deadline=1200s'
      )
      Results::Success.new(guid: guid, analyzer: analyzer).tap do |result|
        JSON.parse(stdout).each do |issue|
          loc = Location.new(
            start_line: issue['line'],
            start_column: nil,
            end_line: nil,
            end_column: nil
          )

          result.add_issue Issue.new(
            path: relative_path(issue['path']),
            location: loc,
            id: Digest::SHA1.hexdigest(issue['message']),
            message: issue['message'],
          )
        end
      end
    end
  end
end
