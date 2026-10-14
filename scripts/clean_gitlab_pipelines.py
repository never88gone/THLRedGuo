#!/usr/bin/env python3
import argparse
import subprocess
import sys

def main():
    parser = argparse.ArgumentParser(description="GitLab 构建记录与产物清理工具（默认保留最近 10 条）")
    parser.add_argument("--keep", type=int, default=10, help="保留最近的流水线条数 (默认: 10)")
    parser.add_argument("--project", type=str, default="MYIT/Product/THLRedLook", help="目标项目完整路径")
    args = parser.parse_args()

    keep_count = args.keep
    project_path = args.project

    ruby_script = f'''
project = Project.find_by_full_path("{project_path}")
if project.nil?
  puts "未找到项目: {project_path}"
  exit 1
end

pipelines = project.ci_pipelines.order(id: :desc)
total_count = pipelines.count
keep_count = {keep_count}

if total_count <= keep_count
  puts "当前流水线数 (\\#{{total_count}}) 未超过保留限制 (\\#{{keep_count}})，无需清理。"
  exit 0
end

to_destroy_ids = pipelines.offset(keep_count).pluck(:id)
puts "项目: \\#{{project.name}}, 当前总流水线数: \\#{{total_count}}, 即将清理 \\#{{to_destroy_ids.count}} 条旧流水线..."

deleted_pipelines = 0
deleted_artifacts = 0

to_destroy_ids.each do |pid|
  pipeline = Ci::Pipeline.find_by(id: pid)
  next unless pipeline
  pipeline.builds.find_each do |build|
    build.job_artifacts.find_each do |artifact|
      artifact.destroy
      deleted_artifacts += 1
    end
  end
  pipeline.destroy
  deleted_pipelines += 1
end

puts "清理成功: 删除了 \\#{{deleted_pipelines}} 条流水线，销毁了 \\#{{deleted_artifacts}} 个旧构建产物包。"
puts "当前剩余流水线数: \\#{{project.ci_pipelines.count}}"
'''

    print(f"正在连接 GitLab 容器清理项目 '{project_path}' 的旧构建（保留最近 {keep_count} 条）...")
    cmd = ["docker", "exec", "gitlab", "gitlab-rails", "runner", ruby_script]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"执行失败: {e.stderr}", file=sys.stderr)
        sys.exit(1)

    print("正在执行 GitLab 孤立构建产物物理文件回收...")
    try:
        cleanup_cmd = ["docker", "exec", "gitlab", "gitlab-rake", "gitlab:cleanup:orphan_job_artifact_files", "DRY_RUN=false"]
        rake_res = subprocess.run(cleanup_cmd, capture_output=True, text=True, check=True)
        for line in rake_res.stdout.splitlines():
            if "cleaned" in line or "Processed" in line:
                print(f"  -> {line.strip()}")
    except Exception as e:
        print(f"物理清理跳过或异常: {e}")

    print("\n✅ GitLab 构建记录已成功对齐为仅保留最近 10 条！")

if __name__ == "__main__":
    main()
