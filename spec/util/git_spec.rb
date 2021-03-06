# Puppet Library
# Copyright (C) 2014 drrb
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'spec_helper'

module PuppetLibrary::Util
    describe Git do
        @@repo_dir = Tempdir.new("git-repo")
        @@tags = [ "0.9.0", "1.0.0-rc1", "1.0.0", "xxx" ]

        before :all do
            def git(command)
                git_command = "git --git-dir=#{@@repo_dir.path}/.git --work-tree=#{@@repo_dir.path} #{command}"
                `#{git_command}`
                unless $?.success?
                    raise "Failed to run command: \"#{git_command}\""
                end
            end

            git "init"
            git "config user.name tester"
            git "config user.email tester@example.com"
            @@tags.each do |tag|
                File.open(File.join(@@repo_dir.path, "Modulefile"), "w") do |modulefile|
                    modulefile.write <<-MODULEFILE
                    name 'puppetlabs-apache'
                    version '#{tag}'
                    author 'puppetlabs'
                    MODULEFILE
                end
                git "add ."
                git "commit --message='Tagging #{tag}'"
                git "tag #{tag}"
            end
        end

        let(:git) { Git.new(@@repo_dir.path, cache_dir) }
        let(:cache_dir) { Tempdir.new("git-cache") }

        context "when a git command returns nonzero" do
            it "raises an error" do
                expect {
                    git.read_file("nonexistant.file", "0.9.0")
                }.to raise_error /Error running Git command/
            end
        end

        describe "#tags" do
            it "lists the tags" do
                @@tags.each { |tag| expect(git.tags).to include tag }
            end
        end

        describe "#with_tag" do
            it "yields to the block with a directory containing the tag" do
                git.with_tag("1.0.0") do |tag_path|
                    modulefile = File.join(tag_path, "Modulefile")
                    expect(File.read(modulefile)).to include "version '1.0.0'"
                end
            end
        end

        describe "#read_file" do
            it "returns the content of the specified file as it was at the specified tag" do
                expect(git.read_file("Modulefile", "0.9.0")).to include "version '0.9.0'"
            end
        end

        describe "#update_cache!" do
            it "clones the git repository to the cache directory" do
                git.update_cache!

                expect(`git --git-dir #{cache_dir.path}/.git remote -v`).to include @@repo_dir.path
            end

            it "creates Git's .git/FETCH_HEAD file so that we know that the cache was recently created" do
                git.update_cache!

                expect(File.exist?(File.join(cache_dir.path, ".git", "FETCH_HEAD"))).to be_true
            end

            it "copes with a missing .git/FETCH_HEAD file" do
                fetch_file = File.join(cache_dir.path, ".git", "FETCH_HEAD")
                git.update_cache!
                rm fetch_file

                git.update_cache!

                expect(File.exist? fetch_file).to be_true
            end

            it "doesn't update the cache if it was recently updated" do
                git.update_cache!
                new_head = Dir.chdir(@@repo_dir.path) do
                    touch "xxx"
                    `git add xxx`
                    `git commit --message='Added file'`
                    `git rev-parse HEAD`
                end

                git.update_cache!

                expect(`git --git-dir #{cache_dir.path}/.git rev-parse HEAD`).not_to eq new_head
            end

            it "updates the cache if it's been long enough" do
                git.update_cache!
                git = Git.new(@@repo_dir.path, cache_dir, 0) # zero second cache TTL
                new_head = Dir.chdir(@@repo_dir.path) do
                    touch "xxx"
                    `git add xxx`
                    `git commit --message='Added file'`
                    `git rev-parse HEAD`
                end

                git.update_cache!

                expect(`git --git-dir #{cache_dir.path}/.git rev-parse HEAD`).to eq new_head
            end
        end

        describe "#clear_cache!" do
            it "deletes the cache directory" do
                git.update_cache!
                git.clear_cache!

                expect(File.exist? cache_dir.path).to be_false
            end
        end
    end
end
