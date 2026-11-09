# Oddaje do kolejki joby workera, który zniknął bez sprzątania. Solid Queue robi to
# sam tylko przy starcie supervisora: gdy supervisor wytnie rekord zamrożonego workera
# (np. po uśpieniu maszyny) i podmieni forka, claimy starego zostają bez procesu
# i review wisi w „describing", choć nic dla niego nie działa.
#
# Najpierw dobijamy sesje claude martwego workera — inaczej oddany job odpaliłby
# drugą, płatną sesję obok wciąż żywej pierwszej.
class OrphanedJobsSweep
  def self.call(orphaned_claims: SolidQueue::ClaimedExecution.orphaned)
    OrphanedRunsCleanup.abort_dead_runs
    orphaned_claims.release_all
  end
end
