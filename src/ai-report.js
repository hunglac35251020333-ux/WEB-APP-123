function mountAIReport(){
  const content=document.querySelector('.content');
  const heading=content?.querySelector('.page-head h1');
  if(!content||!heading||!heading.textContent.includes('Chào buổi sáng'))return;
  if(content.querySelector('.ai-toolbar'))return;
  const toolbar=document.createElement('div');
  toolbar.className='ai-toolbar';
  toolbar.innerHTML='<div><strong>PeopleOps AI</strong><span>Tạo bản tóm tắt điều hành từ dữ liệu nhân sự hiện có</span></div><button class="report-btn">✦ Tạo báo cáo tự động</button>';
  content.insertBefore(toolbar,content.firstChild);
  toolbar.querySelector('button').addEventListener('click',async()=>{
    const button=toolbar.querySelector('button');
    button.disabled=true;button.textContent='Đang phân tích…';
    let panel=content.querySelector('.ai-report');
    if(!panel){panel=document.createElement('section');panel.className='ai-report';toolbar.after(panel)}
    panel.innerHTML='<div class="ai-loading"><i></i><span>AI đang tổng hợp dữ liệu và viết báo cáo điều hành…</span></div>';
    try{
      const employees=JSON.parse(localStorage.getItem('hrm-employees')||'[]');
      const response=await fetch('/api/report',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({employees,generatedAt:new Date().toISOString(),timezone:'Asia/Ho_Chi_Minh'})});
      const data=await response.json();
      if(!response.ok)throw new Error(data.error||'Không thể tạo báo cáo');
      panel.className='ai-report';
      panel.innerHTML='<div class="ai-report-head"><div><span>BÁO CÁO ĐIỀU HÀNH</span><h2>Phân tích nhân sự tự động</h2></div><button>Sao chép</button></div><div class="report-body"></div>';
      panel.querySelector('.report-body').textContent=data.report;
      panel.querySelector('button').onclick=()=>navigator.clipboard.writeText(data.report);
    }catch(error){panel.className='ai-report has-error';panel.innerHTML='<div class="ai-report-head"><div><span>LỖI TẠO BÁO CÁO</span><h2>Chưa thể hoàn tất</h2></div></div><div class="report-body"></div>';panel.querySelector('.report-body').textContent=error.message}
    finally{button.disabled=false;button.textContent='✦ Tạo báo cáo tự động'}
  });
}
const observer=new MutationObserver(mountAIReport);observer.observe(document.documentElement,{childList:true,subtree:true});queueMicrotask(mountAIReport);
