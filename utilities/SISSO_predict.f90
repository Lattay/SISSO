program SISSO_predict
! read the models from SISSO.out and make prediction on test data in predict.dat
! input files: predict.dat which has the same format with that of train.dat
! input files: SISSO_predict_para which contains the needed parameters for this program to run.
!              Format: line1, number of samples in "predict.dat"; 
!                      line2, number of features in "predict.dat"; 
!                      line3, highest descriptor dimension in SISSO.out; 
!                      line4, property type (1:cont., 2: categ.)
!              If this file is missing, the code will ask for input interactively.
! output files: predict_X.out, data of the descriptor components
!               predict_Y.out, data of predicted Y 
! Note: please make sure that no operator symbols appear in the feature names.
! E.g.: if a feature is named 'a', then 'abs()' will be mistakenly translated as xxxbs(), where xxx is the feature value.

integer i,j,k,l,ndim,nd,nf,ns,ptype
character line*100000,pname*50
character,allocatable:: desc(:)*500,allname(:)*50,afname(:)*50,mname(:)*50
real*8 intercept,rmse,maxae
real*8,allocatable:: y(:),af(:,:),dat_desc(:,:),coeff(:),res(:)
logical fexist


inquire(file='SISSO_predict_para',exist=fexist) 
if(fexist) then
 open(1,file='SISSO_predict_para',status='old')
 read(1,*) ns
 read(1,*) nf
 read(1,*) ndim
 read(1,*) ptype
else
 write(6,'(a)') 'Number of test-materials in the file predict.dat:'
 read(5,*) ns
 write(6,'(a)') 'Number of features in the file predict.dat:'
 read(5,*) nf
 write(6,'(a)') 'Highest dimension of the models to be read from SISSO.out:'
 read(5,*) ndim
 write(6,'(a)') 'Property type (1: continuous, 2: categorical): '
 read(5,*) ptype
end if

allocate(desc(ndim))
allocate(allname(nf+2))
allocate(afname(nf))
allocate(mname(ns))
allocate(y(ns))
allocate(af(ns,nf))
allocate(dat_desc(ns,ndim))
allocate(coeff(ndim))
allocate(res(ns))

! predict.dat read in 
open(1,file='predict.dat',status='old')
read(1,'(a)') line
call sepchange(line)
call string_split(line,allname,' ')

if(ptype==1) then
 pname=allname(2)
 afname(:nf)=allname(3:)
else
 afname(:nf)=allname(2:)
end if

do i=1,ns
  read(1,'(a)') line
  call sepchange(line)
  call string_split(line,mname(i:i),' ')
  j=index(line,trim(mname(i)))
  if(ptype==1) then
    read(line(j+len_trim(mname(i)):),*),y(i),af(i,:)
  else
    read(line(j+len_trim(mname(i)):),*),af(i,:)
  end if
end do
close(1)

open(1,file='SISSO.out',status='old')
open(3,file='predict_Y.out',status='replace')
open(4,file='predict_X.out',status='replace')

nd=0
do while(.not. eof(1))
   read(1,'(a)') line
   if(index(line,'D descriptor')/=0) then
      i=index(line,'D descriptor')
      read(line(:i-1),*) nd
      print *,'dimension: ',nd
      
      read(1,'(a)')
      do i=1,nd
        read(1,'(a)') line
        j=index(line,'=')
        k=index(line,'feature_ID')
        desc(i)=line(j+1:k-1)
        desc(i)=trim(adjustl(desc(i)))
        print *,'feature: ',trim(adjustl(desc(i)))
      end do
 
      read(1,'(a)')
      if(ptype==1) then
        read(1,'(a)') line
        j=index(line,':')
        read(line(j+1:),*) coeff(:nd)
        read(1,'(a)') line
        j=index(line,':')
        read(line(j+1:),*) intercept
        print *,'intercept: ',intercept
        print *,'coefficients: ',coeff(:nd)
      end if

      write(4,'(a,i5)') 'Descriptor coordinates at dimension: ',nd
      do i=1,nd
        dat_desc(:,i)=data_of_desc(ns,nf,desc(i),af,afname)
      end do
      do i=1,ns
        write(4,'(<nd>e20.10)') dat_desc(i,:nd)
      end do

      if(ptype==1) then
         write(3,'(a,i5)') 'Predictions (y,pred,y-pred) by the model of dimension: ',nd
         do i=1,ns
         res(i)=y(i)-(intercept+sum(dat_desc(i,:nd)*coeff(:nd)))
         write(3,'(3e20.10)') y(i),(intercept+sum(dat_desc(i,:nd)*coeff(:nd))),res(i)
         end do
         rmse=sqrt(sum(res**2)/ns)
         maxae=maxval(abs(res))
         print *,'RMSE and MaxAE: ',rmse,maxae
         write(3,'(a,2f20.10)') 'Prediction RMSE and MaxAE: ',rmse,maxae
      elseif(ptype==2) then
         write(3,'(a)') 'No prediction data for classification!'
      end if
  end if
     if(nd==ndim) exit
end do


close(1)
close(3)
close(4)
write(6,'(a/)') 'See details in the output files predict_Y.out and predict_X.out!'

deallocate(desc)
deallocate(allname)
deallocate(afname)
deallocate(mname)
deallocate(y)
deallocate(af)
deallocate(dat_desc)
deallocate(coeff)
deallocate(res)

contains

function data_of_desc(ns,nf,desc_str,af,afname)
integer i,j,k,n,ns,nf,imax,length,maxlength
character desc_str*500,afname(nf)*50,desc_expr(ns)*500,op(17)*10
real*8 af(ns,nf),data_of_desc(ns)
logical fexist,isop,isvar

op=(/'+','-','*','/','exp','exp(-','^-1','^2','^3','sqrt','cbrt','log','abs','scd','^6','sin','cos'/)
nop=17
n=0
k=1
desc_expr=''

do while(k<=len_trim(desc_str))
   isop=.false.
   isvar=.false.

   ! detecting operators at potition k:
   maxlength=0
   do i=1,nop  ! find the longest operator that appears in the string
      if(index(desc_str(k:),trim(adjustl(op(i))))==1) then
        length=len_trim(adjustl(op(i)))
        isop=.true.
        if(length>maxlength) then
          maxlength=length
          imax=i
        end if
      end if
   end do
   if(maxlength>0) then ! including the operator
      desc_expr(:)(n+1:n+len_trim(adjustl(op(imax))))=trim(adjustl(op(imax)))
      n=n+len_trim(adjustl(op(imax)))  ! updated length of the string in desc_expr
      k=k+len_trim(adjustl(op(imax)))  ! updated start position in desc_str
   end if

   ! if not operator, detecting variables at position k:
   if(.not. isop) then
      maxlength=0
      do i=1,nf  ! find the longest variable that appear in the descriptor
         if(index(desc_str(k:),trim(adjustl(afname(i))))==1) then
           length=len_trim(adjustl(afname(i)))
           isvar=.true.
           if(length>maxlength) then
             maxlength=length
             imax=i
           end if
         end if
      end do
      if(maxlength>0) then ! recreating the express by replacing the variables with numbers
         do j=1,ns
            write(desc_expr(j)(n+1:n+22),'(a,f20.10,a)') '(',af(j,imax),')'
         end do
         n=n+22  ! updated length of the stringn in desc_expr
         k=k+len_trim(adjustl(afname(imax))) ! updated start position in desc_str
      end if
    end if
 
   ! if not operator and variable
   if( (.not. isop) .and. (.not. isvar) ) then
      desc_expr(:)(n+1:n+1)=desc_str(k:k) 
      n=n+1
      k=k+1
   end if

end do

inquire(file='desc_tmp',exist=fexist)
if(fexist) call system('rm desc_tmp')
do i=1,ns
     call nospace(desc_expr(i))
     call system('echo "define abs(i){if(i<0) return (-i);return(i)} define exp(i){return(e(i))} &
                  define sin(i){return(s(i))}  define log(i){return(l(i))}  &
                  define cbrt(i){ if(i<0) return (-e(l(-i)/3)); if(i==0) return 0; return e(l(i)/3) } &
                  define cos(i){return(c(i))}  define scd(i){ return (1.0/3.14159265/(1+i^2))} &
                  '//trim(adjustl(desc_expr(i)))//' " |bc -l >>desc_tmp')
end do

open (111,file='desc_tmp',status='old')
do i=1,ns
    read(111,*) data_of_desc(i)
end do
close(111)
call system('rm desc_tmp')

end function


subroutine nospace(fname)
character(len=*) fname
character string*500
integer i,j,k
string=''
k=0
do j=1,len_trim(fname)
if(fname(j:j)==' ' .or. fname(j:j)=='') cycle
k=k+1
string(k:k)=fname(j:j)
end do

i=index(string,'exp(-')
if(i>0) then
  fname(:i+3)=string(:i+3)
  fname(i+4:i+4)='0'
  fname(i+5:)=string(i+4:)
else
  fname=string
end if
end subroutine

subroutine string_split(instr,outstr,sp)
! break a string into sub-strings
! input: instr, string; sp, separator
! output: outstr, sub-strings
character(len=*) instr,outstr(:),sp
integer n,i,j,k
logical isend

isend=.false.
n=0
outstr=''

i=index(instr,sp)
if(i/=0) then
  if(i/=1) then
    n=n+1
    outstr(n)=instr(1:i-1)
  end if
  do while ((.not. isend) .and. n<ubound(outstr,1))
    if ((i+len(sp)-1)<len(instr)) then
        j=index(instr(i+len(sp):),sp)
        if(j==0) then
          isend=.true.
          n=n+1
          outstr(n)=instr(i+len(sp):)
        else if(j>1) then
          n=n+1
          outstr(n)=instr(i+len(sp):i+len(sp)-1+j-1)
        end if
        i=i+len(sp)+j-1
     else
       isend=.true.
     end if
  end do
end if

end subroutine

subroutine sepchange(line)
character(len=*) line
do while (index(line,char(9))/=0)   ! separator TAB to space
 line(index(line,char(9)):index(line,char(9)))=' '
end do
do while (index(line,',')/=0)    ! separator comma to space
 line(index(line,','):index(line,','))=' '
end do
end subroutine


end program
