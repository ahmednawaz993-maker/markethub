const {GoogleAuth}=require('google-auth-library');
const fs=require('fs');
const retry=async(f,n=8)=>{for(let i=0;i<n;i++){try{return await f()}catch(e){if(i===n-1)throw e;await new Promise(r=>setTimeout(r,2500))}}};
(async()=>{
  const auth=new GoogleAuth({keyFile:'C:/Users/dell/Downloads/markethub-80276-firebase-adminsdk-fbsvc-32d5cf4e0f.json',
    scopes:['https://www.googleapis.com/auth/cloud-platform']});
  const c=await auth.getClient();
  const r=await retry(()=>c.request({url:'https://firebase.googleapis.com/v1beta1/projects/markethub-80276/androidApps/1:541505846653:android:43c0c2c9c92db4148a2014/config'}));
  const json=Buffer.from(r.data.configFileContents,'base64').toString('utf8');
  fs.writeFileSync('_live_google_services.json',json);
  const d=JSON.parse(json);
  for(const cl of d.client||[]){
    const pkg=cl.client_info.android_client_info.package_name;
    const types=(cl.oauth_client||[]).map(o=>o.client_type);
    console.log(`  ${pkg.padEnd(24)} oauth client types: ${JSON.stringify(types)}`);
    (cl.oauth_client||[]).filter(o=>o.client_type===1).forEach(o=>
      console.log(`      ANDROID client present, cert ${o.android_info.certificate_hash.slice(0,12)}...`));
  }
  process.exit(0);
})();
