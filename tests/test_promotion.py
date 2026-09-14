import unittest
from scripts.promotion import PromotionError, PromotionState, transition
class PromotionTests(unittest.TestCase):
    def test_human_gate_path(self):
        state = transition(PromotionState.REQUESTED, PromotionState.CHECKING)
        state = transition(state, PromotionState.AWAITING_APPROVAL)
        state = transition(state, PromotionState.DEPLOYING)
        self.assertEqual(transition(state, PromotionState.HEALTHY), PromotionState.HEALTHY)
    def test_failed_deploy_can_rollback(self):
        self.assertEqual(transition(PromotionState.DEPLOYING, PromotionState.ROLLING_BACK), PromotionState.ROLLING_BACK)
        self.assertEqual(transition(PromotionState.ROLLING_BACK, PromotionState.ROLLED_BACK), PromotionState.ROLLED_BACK)
    def test_skips_are_rejected(self):
        with self.assertRaises(PromotionError): transition(PromotionState.REQUESTED, PromotionState.DEPLOYING)
if __name__ == '__main__': unittest.main()
