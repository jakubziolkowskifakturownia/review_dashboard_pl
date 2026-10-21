require "test_helper"

class SelfReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:webapp)
    Project.where.not(id: @project.id).update_all(archived_at: Time.current)
  end

  def fake_github(prs: [], error: nil)
    Object.new.tap do |o|
      o.define_singleton_method(:my_open_prs) do |repo:, repo_dir:|
        raise GithubClient::Error, error if error

        prs
      end
    end
  end

  def with_sources(prs: [], branches: [], error: nil, &block)
    GithubClient.stub(:new, fake_github(prs: prs, error: error)) do
      LocalBranches.stub(:new, Struct.new(:branches) { def list(except: []) = branches.reject { |b| except.include?(b.name) } }.new(branches), &block)
    end
  end

  def branch(name, ahead: 2)
    LocalBranches::Branch.new(name: name, ahead: ahead, committed_at: Time.current, worktree_path: nil)
  end

  test "should list my open PRs and local branches without a PR with links to order a review" do
    prs = [ { "number" => 77, "title" => "Poprawka VAT", "url" => "https://github.com/acme/webapp/pull/77",
              "headRefName" => "jz_vat", "isDraft" => false } ]
    with_sources(prs: prs, branches: [ branch("jz_vat"), branch("jz_local") ]) { get self_reviews_path }

    assert_response :success
    assert_select "#self_pr_#{@project.id}_77.qitem a.qttl[href=?]",
                  new_project_review_path(@project, pr_url: prs.first["url"], self: "1"), text: "Poprawka VAT"
    assert_select "#self_branch_#{@project.id}_jz_local.qitem a.qttl[href=?]",
                  new_project_review_path(@project, branch: "jz_local", self: "1")
    assert_select "#self_branches", text: /jz_vat/, count: 0
  end

  test "should link to an existing self review instead of ordering a second one" do
    review = @project.reviews.create!(branch: "jz_local", scope: { "self" => true })
    with_sources(branches: [ branch("jz_local") ]) { get self_reviews_path }

    assert_select "#self_branch_#{@project.id}_jz_local a.qttl[href=?]", review_path(review)
    assert_select "#self_recent #review_queue_#{review.id} a.qttl[href=?]", review_path(review)
  end

  test "should switch the left column between review queues and self review with tabs" do
    get root_path
    assert_select ".dash-tabs a.is-active[href=?]", root_path
    assert_select ".dash-main #queues"
    assert_select ".dash-main #self_recent", count: 0

    with_sources { get self_reviews_path }
    assert_select ".dash-tabs a.is-active[href=?]", self_reviews_path
    assert_select ".dash-main #self_recent"
    assert_select ".dash-main #queues", count: 0
  end

  test "should keep the self review tab when a review is opened by its own address" do
    review = @project.reviews.create!(branch: "jz_local", scope: { "self" => true })
    with_sources { get self_reviews_path }

    with_sources { get review_path(review) }
    assert_select ".dash-main #self_recent"

    get root_path
    with_sources { get review_path(review) }
    assert_select ".dash-main #queues"
  end

  test "should show the gh error and still list local branches" do
    with_sources(branches: [ branch("jz_local") ], error: "gh: not logged in") { get self_reviews_path }

    assert_response :success
    assert_select "#self_prs .empty", text: /gh: not logged in/
    assert_select "#self_branches", text: /jz_local/
  end
end
