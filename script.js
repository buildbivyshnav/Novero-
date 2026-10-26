/* Novero shared script: data, chrome, cards, cart/wishlist (localStorage) */
const CATS=["Women","Men","Kids","Home","Beauty","Electronics","Footwear","Accessories"];
/* Demo products, shown only when Supabase is not connected */
const SAMPLE=CATS.flatMap((c,ci)=>[1,2,3,4].map(i=>{
  const price=499+((ci*4+i)*137%1500),disc=[10,20,30,40,50][(ci+i)%5];
  return{id:"s"+ci+i,name:c+" Essentials "+i,category:c,price,discount_percent:disc,
    image_url:`https://picsum.photos/seed/novero${ci}${i}/400/500`,rating:(3.6+((ci+i)%14)/10).toFixed(1),
    review_count:10+i*7,description:"Demo product. Connect Supabase to show your real products.",
    created_at:new Date(2026,9,1+ci*3+i).toISOString(),stock:20};
}));
const $=(s,r=document)=>r.querySelector(s);
const esc=t=>String(t??"").replace(/[&<>"']/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[m]));
const store={get:k=>{try{return JSON.parse(localStorage.getItem(k))||[]}catch{return[]}},set:(k,v)=>{try{localStorage.setItem(k,JSON.stringify(v))}catch{}}};
const final=p=>Math.round(p.price*(100-(p.discount_percent||0))/100);
const inr=n=>"₹"+Number(n).toLocaleString("en-IN");
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function toast(m){const t=document.createElement("div");t.className="toast";t.textContent=m;document.body.appendChild(t);setTimeout(()=>t.remove(),1800)}

/* Make database rows and demo rows look the same */
function norm(p){
  const imgs=p.images&&p.images.length?p.images:(p.image_url?[p.image_url]:[]);
  return{...p,price:+p.price,discount_percent:p.discount_percent||0,category:p.categories?.name||p.category||"",
    images:imgs,image_url:imgs[0]||"",sizes:p.sizes||[],colors:p.colors||[],
    rating:+p.rating>0?(+p.rating).toFixed(1):"",review_count:p.review_count||0,stock:p.stock??0};
}
/* Loads active products, then filters and sorts in the browser so prices use the discounted price. */
async function getProducts({q="",cat="",max=0,sort="new",limit=60}={}){
  let list;
  if(sb){
    const{data,error}=await sb.from("products").select("*,categories(name)").eq("is_active",true).limit(300);
    if(error)throw error;list=data.map(norm);
  }else list=SAMPLE.map(norm);
  const ql=q.toLowerCase();
  list=list.filter(p=>(!ql||p.name.toLowerCase().includes(ql))&&(!cat||p.category==cat)&&(!max||final(p)<=max));
  const by={
    new:(a,b)=>new Date(b.created_at)-new Date(a.created_at),
    low:(a,b)=>final(a)-final(b),high:(a,b)=>final(b)-final(a),
    rating:(a,b)=>(+b.rating||0)-(+a.rating||0),
    popular:(a,b)=>b.review_count-a.review_count,
    deal:(a,b)=>b.discount_percent-a.discount_percent};
  return list.sort(by[sort]||by.new).slice(0,limit);
}
async function getByIds(ids){
  ids=[...new Set(ids)];
  if(sb){
    ids=ids.filter(i=>UUID.test(i));if(!ids.length)return[];
    const{data,error}=await sb.from("products").select("*,categories(name)").in("id",ids).eq("is_active",true);
    if(error)throw error;return data.map(norm);
  }
  return SAMPLE.map(norm).filter(p=>ids.includes(p.id));
}
function card(p){
  const w=store.get("wish").includes(p.id);
  return `<article class="card"><button class="heart ${w?"on":""}" data-w="${esc(p.id)}" aria-label="Toggle wishlist">${w?"♥":"♡"}</button>
  <a href="product-details.html?id=${encodeURIComponent(p.id)}"><img loading="lazy" src="${esc(p.image_url)}" alt="${esc(p.name)}"></a>
  <div class="in"><h3>${esc(p.name)}</h3><div class="price">₹${final(p)}${p.discount_percent?`<s>₹${p.price}</s><em>${p.discount_percent}% off</em>`:""}</div>
  <span class="rate">${p.rating?esc(p.rating)+" ★":"New"}</span><button class="add" data-c="${esc(p.id)}" ${p.stock<=0?"disabled":""}>${p.stock<=0?"Out of stock":"Add to cart"}</button></div></article>`;
}
function show(el,list){el.innerHTML=list.length?list.map(card).join(""):'<p class="msg">No products found. Try another search or filter.</p>'}
async function load(el,opts){
  el.innerHTML='<div class="spin" style="grid-column:1/-1"></div>';
  try{show(el,await getProducts(opts))}
  catch(e){el.innerHTML='<p class="msg">Could not load products. Check your Supabase setup and try again.</p>'}
}
/* Cart: items are {id,qty,size,color} */
function cartAdd(id,qty=1,size="",color=""){
  const l=store.get("cart"),i=l.find(x=>x.id==id&&(x.size||"")==size&&(x.color||"")==color);
  if(i)i.qty=Math.min(20,i.qty+qty);else l.push({id,qty:Math.min(20,qty),size,color});
  store.set("cart",l);badges();
}
document.addEventListener("click",e=>{
  const w=e.target.closest("[data-w]"),c=e.target.closest("[data-c]");
  if(w){let l=store.get("wish"),id=w.dataset.w,on=l.includes(id);
    l=on?l.filter(x=>x!=id):[...l,id];store.set("wish",l);w.classList.toggle("on",!on);w.textContent=on?"♡":"♥";
    toast(on?"Removed from wishlist":"Saved to wishlist");badges();document.dispatchEvent(new Event("storechange"))}
  if(c){cartAdd(c.dataset.c);toast("Added to cart")}
});
function badges(){const c=store.get("cart").reduce((a,b)=>a+b.qty,0),w=store.get("wish").length;
  document.querySelectorAll("[data-bc]").forEach(n=>n.textContent=c);document.querySelectorAll("[data-bw]").forEach(n=>n.textContent=w)}
/* Returns the logged-in session, or sends the visitor to the login page */
async function needLogin(){
  if(!sb){location.href="login.html";return null}
  const{data:{session}}=await sb.auth.getSession();
  if(!session){location.href="login.html?next="+encodeURIComponent(location.pathname.split("/").pop()+location.search);return null}
  return session;
}
function chrome(active){
  const q=new URLSearchParams(location.search).get("q")||"";
  $("#hdr").innerHTML=`<header><div class="wrap"><div class="bar"><a class="logo" href="index.html" title="Style More. Spend Less.">Nove<b>ro</b></a>
  <form class="search" action="products.html"><input name="q" value="${esc(q)}" placeholder="Search for products" aria-label="Search"><button>Search</button></form>
  <nav class="icons"><a href="login.html" id="acct">Login</a><a href="wishlist.html">Wishlist<span class="badge" data-bw>0</span></a><a href="cart.html">Cart<span class="badge" data-bc>0</span></a></nav></div></div>
  <div class="cats">${CATS.map(c=>`<a href="products.html?cat=${c}">${c}</a>`).join("")}</div></header>`;
  $("#ftr").innerHTML=`<footer><div class="wrap"><strong style="color:var(--pink)">Novero</strong><a href="about.html">About Us</a><a href="contact.html">Contact</a><a href="help.html">Help</a><a href="privacy.html">Privacy Policy</a><a href="terms.html">Terms</a><span>Style More. Spend Less.</span></div></footer>
  <nav class="bn">${[["index.html","⌂","Home"],["products.html","▦","Shop"],["wishlist.html","♡","Wishlist"],["cart.html","🛒","Cart"],["login.html","☺","Account"]].map(([h,i,t])=>`<a href="${h}" class="${h==active?"on":""}"><span>${i}</span>${t}</a>`).join("")}</nav>`;
  badges();
  if(sb)sb.auth.getSession().then(({data})=>{if(data.session)$("#acct").textContent="Account"}).catch(()=>{});
}
