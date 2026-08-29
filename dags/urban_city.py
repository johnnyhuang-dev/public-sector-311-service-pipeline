from datetime import datetime, timedelta

from airflow import DAG
from airflow.sdk import task

from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.providers.microsoft.azure.operators.data_factory import AzureDataFactoryRunPipelineOperator

from include.transform import transform
from include.load_data import upload_data

default_args = {
    'owner': 'orproja',
    'depends_on_past': False, # prevent airflow from executing previously missed tasks
    'start_date': datetime(2026, 8, 26),
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
    'schedule_interval': '@hourly',
    'resource_group_name': 'service_requests',
    'factory_name': '311-service-factory',
    'azure_data_factory_conn_id': 'azure_data_factory'
}

@task()
def extract_api_data():
    api_response = upload_data()

    return api_response

@task()
def transform_data():
    clean_data = transform()

    return clean_data

with DAG(dag_id='urban_city_requests', 
         catchup=False,
         default_args=default_args):
    
    create_db_table = SQLExecuteQueryOperator(
        sql='sql/311_service.sql',
        task_id='311_service_table',
        conn_id='postgres_conn'
    )

    data_factory = AzureDataFactoryRunPipelineOperator(
        task_id='run_data_factory',
        pipeline_name='311ServiceDataFactoryPipeline'
    )
    
    extract_api_data() >> transform_data() >> create_db_table >> data_factory