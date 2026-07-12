extends Node
## Test speciation strategies.
## Run with: godot --headless --path . res://tests/test_speciation.tscn

var tracker: InnovationTracker
var rng: RandomNumberGenerator
var ctx: MutationContext
var similarity: SimilarityTest

func _ready() -> void:
        print("=== test_speciation ===")
        tracker = InnovationTracker.new()
        for i in range(4):
                tracker.reserve_node_id(i)
        rng = RandomNumberGenerator.new()
        rng.seed = 99
        ctx = MutationContext.new(rng, tracker, null)
        similarity = SimilarityTest.Standard.new()

        _test_single()
        _test_standard_creates_new_species_for_distant_genomes()
        _test_standard_adaptive_threshold()
        _test_kmedian()
        _test_purge()

        print("\n=== test_speciation: ALL PASSED ===")
        get_tree().quit()

func _test_single() -> void:
        var genomes: Array = []
        for i in range(5):
                genomes.append(_build_starter_genome())
        var s := SpeciationStrategy.Single.new()
        var species := s.speciate(genomes, [], similarity, ctx)
        assert(species.size() == 1, "Single should produce 1 species, got %d" % species.size())
        assert(species[0].members.size() == 5, "Species should have all 5 genomes")
        print("  single: OK")

func _test_standard_creates_new_species_for_distant_genomes() -> void:
        # Build two distant genomes: one starter, one with many extra connections.
        var close_genomes: Array = []
        for i in range(5):
                close_genomes.append(_build_starter_genome())
        var distant := _build_starter_genome()
        # Add many extra nodes/connections to make it distant.
        for _i in range(15):
                var extra := tracker.new_node_id()
                distant.add_node(NodeGene.new(extra, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
                var innov := tracker.get_connection_innov(0, extra)
                distant.add_connection(ConnectionGene.new(innov, 0, extra, 0.5))
                var innov2 := tracker.get_connection_innov(extra, 3)
                distant.add_connection(ConnectionGene.new(innov2, extra, 3, 0.7))
        var all_genomes := close_genomes.duplicate()
        all_genomes.append(distant)
        var s := SpeciationStrategy.Standard.new(0.5, 5)  # low threshold to trigger speciation
        var species := s.speciate(all_genomes, [], similarity, ctx)
        assert(species.size() >= 2, "Standard should create >=2 species for distant genomes, got %d" % species.size())
        print("  standard distant: OK (%d species)" % species.size())

func _test_standard_adaptive_threshold() -> void:
        # Build many diverse genomes so initial threshold creates lots of species.
        var genomes: Array = []
        for i in range(20):
                var g := _build_starter_genome()
                # Make each unique by adding many disjoints.
                for _j in range(i):
                        var extra := tracker.new_node_id()
                        g.add_node(NodeGene.new(extra, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
                        var innov := tracker.get_connection_innov(0, extra)
                        g.add_connection(ConnectionGene.new(innov, 0, extra, 0.5))
                genomes.append(g)
        var s := SpeciationStrategy.Standard.new(0.5, 5)  # low threshold -> many species
        var threshold_before := s.compatibility_threshold
        var species := s.speciate(genomes, [], similarity, ctx)
        var threshold_after := s.compatibility_threshold
        # Should have raised threshold (since count > target).
        assert(threshold_after > threshold_before, "Adaptive threshold should increase when too many species")
        print("  adaptive threshold: OK (species=%d, threshold %.3f -> %.3f)" % [species.size(), threshold_before, threshold_after])

func _test_kmedian() -> void:
        # Build 2 distinct clusters of genomes.
        var genomes: Array = []
        # Cluster A: starter genomes.
        for i in range(5):
                genomes.append(_build_starter_genome())
        # Cluster B: starter + extra hidden chain.
        for i in range(5):
                var g := _build_starter_genome()
                var extra := tracker.new_node_id()
                g.add_node(NodeGene.new(extra, NodeGene.Kind.HIDDEN, ActivationFunctions.Func.TANH))
                var innov := tracker.get_connection_innov(0, extra)
                g.add_connection(ConnectionGene.new(innov, 0, extra, 0.5))
                var innov2 := tracker.get_connection_innov(extra, 3)
                g.add_connection(ConnectionGene.new(innov2, extra, 3, 0.7))
                genomes.append(g)
        var s := SpeciationStrategy.KMedian.new(2, 3)
        var species := s.speciate(genomes, [], similarity, ctx)
        assert(species.size() == 2, "KMedian with k=2 should produce 2 species, got %d" % species.size())
        print("  kmedian: OK (%d species)" % species.size())

func _test_purge() -> void:
        # First generation: purge should keep top N genomes as seeds, fill with
        # mutated clones, and produce N species.
        var genomes: Array = []
        for i in range(10):
                var g := _build_starter_genome()
                g.fitness = float(i)  # last is best
                genomes.append(g)
        var pol := MutationPolicy.General.new(true, 1.0)
        pol.weight_selector = WeightSelector.Standard.new(1, 1.0)
        pol.weight_mutator = WeightMutator.Standard.new(-0.5, 0.5)
        var purge := SpeciationStrategy.Purge.new(pol, null, 3)  # target 3 species
        var species := purge.speciate(genomes, [], similarity, ctx)
        assert(species.size() == 3, "Purge first-gen should produce 3 species (target), got %d" % species.size())
        # Total members should still be 10.
        var total_members: int = 0
        for sp: Species in species:
                total_members += sp.members.size()
        assert(total_members == 10, "Should still have 10 genomes, got %d" % total_members)
        # Genomes should be mutated (weights differ from originals).
        var any_mutated := false
        for sp: Species in species:
                for g: Genome in sp.members:
                        for c: ConnectionGene in g.connections.values():
                                if absf(c.weight - 0.5) > 1e-3 and absf(c.weight - (-0.5)) > 1e-3 and absf(c.weight - 0.3) > 1e-3:
                                        any_mutated = true
                                        break
                        if any_mutated:
                                break
                if any_mutated:
                        break
        assert(any_mutated, "Purge should mutate the cloned genomes")
        print("  purge: OK (species=%d, threshold=%.3f)" % [species.size(), purge.ideal_threshold])

func _build_starter_genome() -> Genome:
        var g := Genome.new()
        g.add_node(NodeGene.new(0, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR))
        g.add_node(NodeGene.new(1, NodeGene.Kind.INPUT, ActivationFunctions.Func.LINEAR))
        g.add_node(NodeGene.new(2, NodeGene.Kind.BIAS, ActivationFunctions.Func.LINEAR))
        g.add_node(NodeGene.new(3, NodeGene.Kind.OUTPUT, ActivationFunctions.Func.TANH))
        g.add_connection(ConnectionGene.new(tracker.get_connection_innov(0, 3), 0, 3, 0.5))
        g.add_connection(ConnectionGene.new(tracker.get_connection_innov(1, 3), 1, 3, -0.5))
        g.add_connection(ConnectionGene.new(tracker.get_connection_innov(2, 3), 2, 3, 0.3))
        return g
