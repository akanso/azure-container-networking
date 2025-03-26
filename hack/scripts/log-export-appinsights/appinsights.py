import os
import logging
from opencensus.ext.azure.log_exporter import AzureLogHandler

logger = logging.getLogger('cilium-log-exporter')
logger.setLevel(logging.INFO)

instrumentation_key = os.environ.get('APPINSIGHTS_INSTRUMENTATIONKEY')
if instrumentation_key:
    azure_handler = AzureLogHandler(instrumentation_key=instrumentation_key)
    logger.addHandler(azure_handler)

console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_handler.setFormatter(logging.Formatter('%(asctime)s - %(message)s'))
logger.addHandler(console_handler)

log_path = '/host/var/log/cilium/cilium-agent.log'
with open(log_path, 'r') as f:
    f.seek(0, 2)
    while True:
        line = f.readline()
        if line:
            logger.info(line.strip(), extra={
                'custom_dimensions': {
                    'source': 'cilium-agent',
                    'node': os.uname().nodename
                }
            })

