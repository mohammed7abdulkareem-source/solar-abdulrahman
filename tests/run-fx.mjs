import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
const database=process.env.SOLAR_TEST_DATABASE||'solar_fx_clean';
if(!/^solar_[a-z_]+$/.test(database))throw new Error('Dedicated fixture DB required');
const env={...process.env};for(const k of ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH'])delete env[k];
function sql(db,input){const r=spawnSync('docker',['--host=unix:///var/run/docker.sock','exec','-i','solar-customers-postgres','psql','-U','postgres','-d',db,'-q','-v','ON_ERROR_STOP=1'],{input,env,encoding:'utf8'});if(r.status)throw new Error(r.stderr+'\n'+r.stdout);return r.stdout;}
sql('postgres',`create database ${database} template solar_supplier_sql;`);
sql(database,readFileSync('supabase/migrations/20261017144659_supplier_multicurrency_wallets.sql','utf8'));
console.log(sql(database,readFileSync('tests/fx-rollback.sql','utf8')));
