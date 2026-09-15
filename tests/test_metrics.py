import unittest
from scripts.metrics import MetricEvent, MetricsError, promotion_allowed, rollback_required

class MetricsTests(unittest.TestCase):
    def test_minimum_event_accepts_unknown_extensions(self):
        event = MetricEvent.from_mapping({"name":"run.completed","occurred_at":"2026-09-14T00:00:00Z","service":"demo","environment":"production","run_id":"r1","status":"ok","new_metric":3})
        self.assertEqual(event.extensions["new_metric"], 3)
    def test_rejects_timezone_less_timestamp(self):
        with self.assertRaises(MetricsError):
            MetricEvent.from_mapping({"name":"x","occurred_at":"2026-09-14T00:00:00","service":"s","environment":"local","run_id":"r","status":"ok"})
    def test_promotion_requires_human_gate(self):
        self.assertFalse(promotion_allowed(checks_passed=True, human_approved=False))
        self.assertTrue(promotion_allowed(checks_passed=True, human_approved=True))
    def test_rollback_on_any_safety_failure(self):
        self.assertTrue(rollback_required(deploy_failed=False, health_failed=True, regression=False))
        self.assertFalse(rollback_required(deploy_failed=False, health_failed=False, regression=False))

if __name__ == '__main__': unittest.main()
