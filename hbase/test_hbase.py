import unittest
from parameterized import parameterized

from integration_tests.dataproc_test_case import DataprocTestCase


class HBaseTestCase(DataprocTestCase):
    COMPONENT = 'hbase'
    INIT_ACTION = 'gs://dataproc-initialization-actions/hbase/hbase.sh'

    def verify_instance(self, name):
        ret_code, stdout, stderr = self.run_command(
            'gcloud compute ssh {} --command '
            '"/etc/hbase/bin/hbase org.apache.hadoop.hbase.IntegrationTestsDriver -r {}"'.format(
                name,
                "org.apache.hadoop.hbase.mapreduce.IntegrationTestImportTsv"
            )
        )
        self.assertEqual(ret_code, 0, "Failed to validate cluster. Error: {}".format(stderr))

    """
    Single and standard mode on 1.0 and 1.1 are disabled because HBase doesn't work in those 
    modes on older dataproc versions. HBase is intended to run on HA environment.
    HA mode on 1.0 and 1.1 doesn't pass integration test.
    """
    @parameterized.expand([
        # ("SINGLE", "1.0", ["m"]),
        # ("STANDARD", "1.0", ["m"]),
        # ("HA", "1.0", ["m-0"]),
        # ("SINGLE", "1.1", ["m"]),
        # ("STANDARD", "1.1", ["m"]),
        # ("HA", "1.1", ["m-0"]),
        ("SINGLE", "1.2", ["m"]),
        ("STANDARD", "1.2", ["m"]),
        ("HA", "1.2", ["m-0"]),
        ("SINGLE", "1.3", ["m"]),
        ("STANDARD", "1.3", ["m"]),
        ("HA", "1.3", ["m-0"]),
    ], testcase_func_name=DataprocTestCase.generate_verbose_test_name)
    def test_hbase(self, configuration, dataproc_version, machine_suffixes):
        self.createCluster(configuration, self.INIT_ACTION, dataproc_version)
        for machine_suffix in machine_suffixes:
            self.verify_instance(
                "{}-{}".format(
                    self.getClusterName(),
                    machine_suffix
                )
            )


if __name__ == '__main__':
    unittest.main()
