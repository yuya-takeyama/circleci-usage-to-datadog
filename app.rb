require 'net/http'
require 'json'
require 'dogapi'

METRIC_NAMESPACE = 'circleci.usage.'
DOG = Dogapi::Client.new(ENV.fetch('DATADOG_API_KEY'))

def send_metric(time:, metric:, type:, value:, tags: [])
  metric = METRIC_NAMESPACE + metric
  warn({time: time, metric: metric, type: type, value: value, tags: tags}.to_json)
  DOG.emit_point(metric, value, timestamp: time, type: type, tags: tags)
end

query_body = DATA.read
query = {
  'operationName' => "Usage",
  'variables' => {
    'orgId' => ENV.fetch('CIRCLECI_ORG_ID'),
  },
  'query' => query_body,
}

loop do
  time = Time.now
  uri = URI('https://circleci.com/graphql-unstable')

  req = Net::HTTP::Post.new(uri)
  req.body = query.to_json
  req['Content-Type'] = 'application/json'
  req['Authorization'] = ENV.fetch('CIRCLECI_API_TOKEN')

  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request(req)
  end

  data = JSON.parse(res.body).dig('data', 'plan', 'billingPeriods', 0, 'metrics')

  metrics = {
    active_users: data.dig('activeUsers', 'totalCount'),
    projects: data.dig('projects', 'totalCount'),
    total: {
      credits: data.dig('total', 'credits'),
      seconds: data.dig('total', 'seconds'),
    },
    per_project: data.dig('byProject', 'nodes').map { |project|
      {
        project: project.dig('project', 'name'),
        credits: project.dig('aggregate', 'credits'),
        seconds: project.dig('aggregate', 'seconds'),
        dlc_credits: project.dig('aggregate', 'dlcCredits'),
        compute_credits: project.dig('aggregate', 'computeCredits'),
      }
    },
  }

  send_metric(time: time, metric: 'active_users', type: 'gauge', value: metrics[:active_users])
  send_metric(time: time, metric: 'projects', type: 'gauge', value: metrics[:projects])
  send_metric(time: time, metric: 'total.credits', type: 'gauge', value: metrics[:total][:credits])
  send_metric(time: time, metric: 'total.seconds', type: 'gauge', value: metrics[:total][:seconds])

  metrics[:per_project].each do |metric|
    next unless metric[:project] == 'monorepo'
    tags = ["reponame:#{metric[:project]}"]
    send_metric(time: time, metric: 'per_project.credits', type: 'gauge', value: metric[:credits], tags: tags)
    send_metric(time: time, metric: 'per_project.seconds', type: 'gauge', value: metric[:seconds], tags: tags)
    send_metric(time: time, metric: 'per_project.dlc_credits', type: 'gauge', value: metric[:dlc_credits], tags: tags)
    send_metric(time: time, metric: 'per_project.compute_credits', type: 'gauge', value: metric[:compute_credits], tags: tags)
  end

  sleep 15
end

__END__
query Usage($orgId: String!) {
  plan(orgId: $orgId) {
    billingPeriods(numPeriods: 1) {
      metrics {
        activeUsers {
          totalCount
        }
        projects(filter: {usingDLC: true}) {
          totalCount
        }
        total {
          credits
          seconds
        }
        byProject {
          nodes {
            aggregate {
              credits
              seconds
              dlcCredits
              computeCredits
            }
            project {
              name
            }
          }
        }
      }
    }
  }
}
