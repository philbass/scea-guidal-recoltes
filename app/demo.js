/* =====================================================================
   SCEA Guidal · MODE DÉMO
   Faux serveur qui imite Supabase avec des données fictives, gardées
   dans le navigateur. Activé seulement avec « ?demo » dans l'adresse.
   Ne touche jamais la vraie base.
   ===================================================================== */
(function(){
"use strict";
const KEY="guidal.demo.db",SKEY="guidal.demo.session";
const pad=n=>String(n).padStart(2,"0");
const iso=d=>d.getFullYear()+"-"+pad(d.getMonth()+1)+"-"+pad(d.getDate());

function seed(){
  let r=12345;const rnd=()=>(r=(r*16807)%2147483647)/2147483647;
  const db={_id:1000,
    profils:[{id:"demo-resp",identifiant:"admin",nom:"Responsable (démo)",role:"responsable",actif:true},
             {id:"demo-chef",identifiant:"julien",nom:"Julien M. (démo)",role:"chef",actif:true}],
    invitations:[],
    saisonniers:[["COSTA","Maria"],["DUBOIS","Marc"],["MARTINS","Rui"],["PEREIRA","Ana"],["SILVA","João"],["SOUSA","Paulo"],["FERREIRA","Inês"]]
      .map(([nom,prenom],i)=>({id:i+1,nom,prenom,actif:i<6})),
    legumes:[["Radis","Rabanete","colis"],["Oignons blancs","Cebola branca","colis"],["Oignons rouges","Cebola roxa","colis"],["Ciboule","Cebolinho","colis"],["Persil","Salsa","colis"],
      ["Persil scotch","Salsa scotch","unite"],["Épluchage","Descasque","heure"],["Plantation","Plantação","heure"],["Binage","Sacha","heure"],["Chou-fleur","Couve-flor","heure"],
      ["Chou vert","Couve verde","heure"],["Chou blanc","Couve branca","heure"],["Chou rouge","Couve roxa","heure"],["Courgette","Curgete","heure"],["Panais","Pastinaca","heure"],
      ["Céleri branche","Aipo","heure"],["Brocoli","Brócolos","heure"]].map(([nom,nom_pt,mode],i)=>({id:i+1,nom,nom_pt,mode,actif:true,ordre:i+1})),
    tarifs:[],smic:[],recoltes:[],presences:[]};
  const now=new Date(),y=now.getFullYear(),m=now.getMonth();
  const start=iso(new Date(y,m-1,1));
  const prix={1:7,2:6.5,3:6.5,4:6,5:6,6:0.35};
  for(let id=1;id<=17;id++)db.tarifs.push({id:db._id++,legume_id:id,prix:prix[id]||12,depuis:start});
  db.smic.push({depuis:start,taux:12});
  for(let d=new Date(y,m-1,1);d<=now;d.setDate(d.getDate()+1)){
    if(d.getDay()===0||d.getDay()===6)continue;
    const ds=iso(d);
    for(const s of db.saisonniers){
      if(!s.actif||rnd()<0.12)continue;
      const short=s.id===6&&rnd()<0.6;
      const md=rnd()<0.5?"07:00":"07:30",ad=rnd()<0.5?"13:00":"13:30",af=short?"15:00":(rnd()<0.5?"17:00":"16:30");
      db.presences.push({id:db._id++,date:ds,saisonnier_id:s.id,matin_debut:md,matin_fin:"12:00",am_debut:ad,am_fin:af,saisi_par:"demo-chef",corrige_par:null});
      const add=(l,q)=>db.recoltes.push({id:db._id++,date:ds,saisonnier_id:s.id,legume_id:l,quantite:q,saisi_par:"demo-chef",corrige_par:null});
      const mins=t=>{const [h,m]=t.split(":").map(Number);return h*60+m};
      if(s.id===2){add(8,(mins("12:00")-mins(md)+mins(af)-mins(ad))/60);continue}
      if(short){add(1,Math.round(4+rnd()*4));continue}
      add([1,1,2,3,4,5][Math.floor(rnd()*6)],Math.round(13+rnd()*8));
      if(s.id===3)add(6,Math.round(80+rnd()*60));
      if(rnd()<0.6)add([7,9,10,15,16][Math.floor(rnd()*5)],[2,2.5,3][Math.floor(rnd()*3)]);
    }
  }
  return db;
}
let db;
try{db=JSON.parse(localStorage.getItem(KEY))}catch(e){}
if(!db||!db.presences)db=seed();
const save=()=>{try{localStorage.setItem(KEY,JSON.stringify(db))}catch(e){}};
save();

let session=null;try{session=JSON.parse(sessionStorage.getItem(SKEY))}catch(e){}
const listeners=[];
const uid=()=>session&&session.user.id;
const role=()=>{const p=db.profils.find(x=>x.id===uid());return p&&p.actif?p.role:null};
const err=m=>({data:null,error:{message:m}});
const todayIso=()=>iso(new Date());
const daysAgo=n=>{const d=new Date();d.setDate(d.getDate()-n);return iso(d)};
const PRIVATE=["tarifs","smic","invitations"];

function stamp(table,row,isNew,old){
  if(table!=="recoltes"&&table!=="presences")return;
  if(isNew){row.saisi_par=uid();row.corrige_par=null}
  else{row.saisi_par=old.saisi_par;row.corrige_par=uid()!==old.saisi_par?uid():old.corrige_par}
}
function chefDateOk(table,date){
  if(table!=="recoltes"&&table!=="presences")return true;
  return role()==="responsable"||(role()==="chef"&&date>=daysAgo(7)&&date<=todayIso());
}

class Q{
  constructor(t){this.t=t;this.op="select";this.f=[];this.ord=[];this.rng=null;this.one=false;this.ret=false;this.p=null;this.opts={}}
  select(){if(this.op!=="select")this.ret=true;return this}
  eq(c,v){this.f.push(r=>String(r[c])===String(v));return this}
  gte(c,v){this.f.push(r=>r[c]>=v);return this}
  lte(c,v){this.f.push(r=>r[c]<=v);return this}
  order(c){this.ord.push(c);return this}
  range(a,b){this.rng=[a,b];return this}
  maybeSingle(){this.one=true;return this}
  insert(p){this.op="insert";this.p=p;return this}
  upsert(p,o){this.op="upsert";this.p=p;this.opts=o||{};return this}
  update(p){this.op="update";this.p=p;return this}
  delete(){this.op="delete";return this}
  then(res,rej){return new Promise(r=>setTimeout(r,60)).then(()=>this.run()).then(res,rej)}
  run(){
    if(!uid())return err("permission denied");
    const t=this.t,rows=db[t];if(!rows)return err("table inconnue "+t);
    const isResp=role()==="responsable";
    if(!role())return err("permission denied");
    const match=rows.filter(r=>this.f.every(fn=>fn(r)));
    if(this.op==="select"){
      let out=match;
      if(PRIVATE.includes(t)&&!isResp)out=[];
      if(t==="profils"&&!isResp)out=out.filter(r=>r.id===uid());
      if((t==="recoltes"||t==="presences")&&!isResp)out=out.filter(r=>r.date>=daysAgo(7));
      out=out.slice().sort((a,b)=>{for(const c of this.ord){if(a[c]<b[c])return -1;if(a[c]>b[c])return 1}return 0});
      if(this.rng)out=out.slice(this.rng[0],this.rng[1]+1);
      out=JSON.parse(JSON.stringify(out));
      return {data:this.one?(out[0]||null):out,error:null};
    }
    if(!isResp&&t!=="recoltes"&&t!=="presences")return err("new row violates row-level security policy");
    if(this.op==="insert"||this.op==="upsert"){
      const list=Array.isArray(this.p)?this.p:[this.p];const keys=(this.opts.onConflict||"").split(",").filter(Boolean);
      for(const p of list){
        if(!chefDateOk(t,p.date))return err("new row violates row-level security policy");
        const ex=keys.length?rows.find(r=>keys.every(k=>String(r[k])===String(p[k]))):(t==="invitations"?rows.find(r=>r.identifiant===p.identifiant):null);
        if(ex){Object.assign(ex,p)}
        else{const row={...p};if(row.id==null)row.id=t==="profils"?"demo-"+db._id++:db._id++;if(row.actif==null&&["saisonniers","legumes","profils"].includes(t))row.actif=true;stamp(t,row,true);rows.push(row)}
      }
      save();return {data:null,error:null};
    }
    if(this.op==="update"){
      for(const r of match){if(!chefDateOk(t,r.date))return err("permission denied");const old={...r};Object.assign(r,this.p);stamp(t,r,false,old)}
      save();return {data:this.ret?match.map(r=>({id:r.id})):null,error:null};
    }
    if(this.op==="delete"){
      for(const r of match)if(!chefDateOk(t,r.date))return err("permission denied");
      db[t]=rows.filter(r=>!match.includes(r));save();return {data:null,error:null};
    }
  }
}

function journee({p_date,p_saisonnier,p_quantites,p_horaires}){
  if(!chefDateOk("recoltes",p_date))return err("new row violates row-level security policy");
  for(const [k,v] of Object.entries(p_quantites||{})){
    const ex=db.recoltes.find(r=>r.date===p_date&&r.saisonnier_id==p_saisonnier&&r.legume_id==k);
    if(Number(v)>0){if(ex){if(Number(ex.quantite)!==Number(v)){const old={...ex};ex.quantite=Number(v);stamp("recoltes",ex,false,old)}}
      else{const row={id:db._id++,date:p_date,saisonnier_id:Number(p_saisonnier),legume_id:Number(k),quantite:Number(v)};stamp("recoltes",row,true);db.recoltes.push(row)}}
    else if(ex)db.recoltes=db.recoltes.filter(r=>r!==ex);
  }
  const h=p_horaires||{};const v=k=>h[k]||null;
  const ex=db.presences.find(r=>r.date===p_date&&r.saisonnier_id==p_saisonnier);
  if(!v("matin_debut")&&!v("matin_fin")&&!v("am_debut")&&!v("am_fin")){if(ex)db.presences=db.presences.filter(r=>r!==ex)}
  else{const vals={matin_debut:v("matin_debut"),matin_fin:v("matin_fin"),am_debut:v("am_debut"),am_fin:v("am_fin")};
    if(ex){if(JSON.stringify([ex.matin_debut,ex.matin_fin,ex.am_debut,ex.am_fin])!==JSON.stringify(Object.values(vals))){const old={...ex};Object.assign(ex,vals);stamp("presences",ex,false,old)}}
    else{const row={id:db._id++,date:p_date,saisonnier_id:Number(p_saisonnier),...vals};stamp("presences",row,true);db.presences.push(row)}}
  save();return {data:null,error:null};
}

const setSession=s=>{session=s;try{s?sessionStorage.setItem(SKEY,JSON.stringify(s)):sessionStorage.removeItem(SKEY)}catch(e){}};
const emit=ev=>listeners.forEach(fn=>fn(ev,session));
window.GUIDAL_DEMO={
  reset(){try{localStorage.removeItem(KEY)}catch(e){}location.reload()},
  from:t=>new Q(t),
  rpc:async(name,args)=>{await new Promise(r=>setTimeout(r,80));
    if(name==="enregistrer_journee")return journee(args);
    if(role()!=="responsable")return err("Réservé au responsable");
    if(name==="changer_identifiant"){const p=db.profils.find(x=>x.id===args.p_user);if(p){p.identifiant=args.p_ident;save()}return {data:null,error:null}}
    return {data:null,error:null}},
  auth:{
    getSession:async()=>({data:{session}}),
    onAuthStateChange:fn=>{listeners.push(fn);return {data:{subscription:{unsubscribe(){}}}}},
    signInWithPassword:async({email})=>{const id=email.split("@")[0];const p=db.profils.find(x=>x.identifiant===id);
      if(!p)return {error:{message:"Invalid login credentials"}};setSession({user:{id:p.id}});setTimeout(()=>emit("SIGNED_IN"),0);return {error:null}},
    signOut:async()=>{setSession(null);setTimeout(()=>emit("SIGNED_OUT"),0);return {error:null}}
  },
  channel:()=>({on(){return this},subscribe(){return this}}),
  removeChannel(){}
};
})();
