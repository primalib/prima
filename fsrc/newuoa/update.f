      subroutine update(n, npt, bmat, zmat, idz, vlag, beta, knew)
      ! UPDATE updates arrays BMAT and ZMAT together with IDZ, in order
      ! to shift the interpolation point that has index KNEW. On entry, 
      ! VLAG contains the components of the vector THETA*WCHECK + e_b 
      ! of the updating formula (6.11) in the NEWUOA paper, and BETA
      ! holds the value of the parameter that has this name. 
      
      ! Although VLAG will be modified below, its value will NOT be used 
      ! by other parts of NEWUOA after returning from update. Its value 
      ! will be overwritten when trying the alternative model or by
      ! VLAGBETA.

      use consts, only : one, zero
      use lina
      implicit none

      integer, intent(in) :: n, npt, knew
      integer, intent(inout) :: idz
      real(kind=rp), intent(in) :: beta
      real(kind=rp), intent(inout) :: bmat(n, npt+n), zmat(npt,npt-n-1),&
     & vlag(npt + n)

      integer :: iflag, j, ja, jb, jl
      real(kind=rp) :: c, s, r, alpha, denom, scala, scalb, tau, tausq, &
     & temp, tempa, tempb, ztemp(npt), w(npt + n), v1(n), v2(n)

          
      ! Apply the rotations that put zeros in the KNEW-th row of ZMAT.
      ! A Givens rotation will be multiplied to ZMAT from the left so
      ! ZMAT(KNEW, JL) becomes SQRT(ZMAT(KNEW, JL)^2+ZMAT(KNEW,J)) and
      ! ZMAT(KNEW, J) becomes 0. 
      jl = 1  ! For J = 2, ..., IDZ - 1, set JL = 1.
      do j = 2, idz - 1
          if (abs(zmat(knew, j)) >  zero) then
              !call givens(zmat(knew, jl), zmat(knew, j), c, s, r)
              c = zmat(knew, jl)
              s = zmat(knew, j)
              r = sqrt(c**2 + s**2)  
              ! Fortran 2008 can calculate r by the HYPOT intrinsic,
              ! which can avoid over/underflow due to the squres.
              ! r = hypot(c, s) 
              c = c/r
              s = s/r
              ztemp = zmat(:, j)
              zmat(:, j) = c*ztemp - s*zmat(:, jl)
              zmat(:, jl) = c*zmat(:, jl) + s*ztemp
              zmat(knew, j) = zero
      !----------------------------------------------------------------!
              !!! In later vesions, we will include the following line.
              !!! For the moment, we exclude it to align with Powell's 
              !!! version.
!-------------!zmat(knew, jl) = r  !-----------------------------------! 
      !----------------------------------------------------------------!
          end if
      end do

      if (idz <= npt - n - 1) then
          jl = idz  ! For J = IDZ + 1, ..., NPT - N - 1, set JL = IDZ.
      end if
      do j = idz + 1, npt - n - 1
          if (abs(zmat(knew, j)) >  zero) then
              !call givens(zmat(knew, jl), zmat(knew, j), c, s, r)
              c = zmat(knew, jl)
              s = zmat(knew, j)
              r = sqrt(c**2 + s**2)  
              ! Fortran 2008 can calculate r by the HYPOT intrinsic,
              ! which can avoid over/underflow due to the squres.
              !r = hypot(c, s) 
              c = c/r
              s = s/r
              ztemp = zmat(:, j)
              zmat(:, j) = c*ztemp - s*zmat(:, jl)
              zmat(:, jl) = c*zmat(:, jl) + s*ztemp
              zmat(knew, j) = zero
      !----------------------------------------------------------------!
              !!! In later vesions, we will include the following line.
              !!! For the moment, we exclude it to align with Powell's 
              !!! version.
!-------------!zmat(knew, jl) = r  !-----------------------------------! 
      !----------------------------------------------------------------!
          end if
      end do
      
      ! JL plays an important role below. There are two possibilities:
      ! JL = 1 < IDZ iff IDZ = 1 
      ! JL = IDZ > 1 iff 2 <= IDZ <= NPT - N - 1

      ! Put the first NPT components of the KNEW-th column of HLAG into 
      ! W, and calculate the parameters of the updating formula.
      tempa = zmat(knew, 1)
      if (idz >=  2) then
          tempa = -tempa
      end if

      w(1 : npt) = tempa*zmat(:, 1)
      if (jl > 1) then
          tempb = zmat(knew, jl)
          w(1 : npt) = w(1 : npt) + tempb*zmat(:, jl)
      end if

      alpha = w(knew)
      tau = vlag(knew)
      tausq = tau*tau
      denom = alpha*beta + tausq
      vlag(knew) = vlag(knew) - one
      
      ! Complete the updating of ZMAT when there is only one nonzero
      ! element in the KNEW-th row of the new matrix ZMAT, but, if
      ! IFLAG is set to one, then the first column of ZMAT will be 
      ! exchanged with another one later.
      iflag = 0
      if (jl == 1) then
          ! There is only one nonzero in ZMAT(KNEW, :) after the
          ! rotation. This is the normal case, because IDZ is 1 in
          ! precise arithmetic. 
          temp = sqrt(abs(denom))
          tempb = tempa/temp
          tempa = tau/temp
          zmat(:, 1) = tempa*zmat(:, 1) - tempb*vlag(1 : npt)
      !----------------------------------------------------------------!
          if (idz == 1 .and. temp < zero) then
!---------!if (idz == 1 .and. denom < zero) then !---------------------!
      !----------------------------------------------------------------!
              ! TEMP < ZERO?!! Powell wrote this but it is STRANGE!!!!!!
              !!! It is probably a BUG !!!
              ! According to (4.18) of the NEWUOA paper, the 
              ! "TEMP < ZERO" here and "TEMP >= ZERO" below should be
              ! revised by replacing "TEMP" with DENOM, which is denoted
              ! by sigma in the paper. See also the corresponding part
              ! of the LINCOA code (which has also some strangeness).
              ! It seems that the BOBYQA code does not have this part
              ! --- it does not have IDZ at all (why?).
              idz = 2
          end if
      !----------------------------------------------------------------!
          if (idz >= 2 .and. temp >= zero) then 
!---------!if (idz >= 2 .and. denom >= zero) then !--------------------!
      !----------------------------------------------------------------!
              ! JL = 1 and IDZ >= 2??? Seems not possible either!!!
              iflag = 1
          end if
      else
          ! Complete the updating of ZMAT in the alternative case.
          ! There are two nonzeros in ZMAT(KNEW, :) after the rotation.
          ja = 1
          if (beta >=  zero) then 
              ja = jl
          end if
          jb = jl + 1 - ja
          temp = zmat(knew, jb)/denom
          tempa = temp*beta
          tempb = temp*tau
          temp = zmat(knew, ja)
          scala = one/sqrt(abs(beta)*temp*temp + tausq)
          scalb = scala*sqrt(abs(denom))
          zmat(:, ja) = scala*(tau*zmat(:, ja) - temp*vlag(1 : npt))
          zmat(:, jb) = scalb*(zmat(:, jb) - tempa*w(1 : npt) -         &
     &     tempb*vlag(1 : npt))
          
          if (denom <=  zero) then
              if (beta < zero) then 
                  idz = idz + 1  ! Is it possible to get IDZ > NPT-N-1?
              end if
              if (beta >=  zero) then 
                  iflag = 1
              end if
          end if
      end if
      
      ! IDZ is reduced in the following case,  and usually the first
      ! column of ZMAT is exchanged with a later one.
      if (iflag == 1) then
          idz = idz - 1
          if (idz > 1) then
              ztemp = zmat(:, 1)
              zmat(:, 1) = zmat(:, idz)
              zmat(:, idz) = ztemp
          end if
      end if
      
      ! Finally,  update the matrix BMAT.
      w(npt + 1 : npt + n) = bmat(:, knew)
      v1 = (alpha*vlag(npt+1 : npt+n) - tau*w(npt+1 : npt+n))/denom
      v2 = (-beta*w(npt+1 : npt+n) - tau*vlag(npt+1 : npt+n))/denom

!      !-------------------POWELL'S IMPLEMENTATION----------------------!
!      do j = 1, n
!          bmat(j, 1 : npt + j) = bmat(j, 1 : npt + j) +                 &
!     &     v1(j)*vlag(1 : npt + j) + v2(j)*w(1 : npt + j)
!      ! Set the upper triangular part of BMAT(:,NPT+1:NPT+N) by symmetry
!      ! Note that SHIFTBASE sets the lower triangular part by copying
!      ! the upper triangular part, but here it does the opposite. There 
!      ! seems not any particular reason to keep them different. It was
!      ! probably an ad-hoc decision that Powell made when coding. 
!          bmat(1 : j - 1, npt + j) = bmat(j, npt + 1 : npt + j - 1)
!      end do 
!      !---------------POWELL'S IMPLEMENTATION ENDS---------------------!

      !-----------------MATRIX-VECTOR IMPLEMENTATION-------------------!
      bmat = bmat + outprod(v1, vlag) + outprod(v2, w)
      ! Set the upper triangular part of BMAT(:,NPT+1:NPT+N) by symmetry
      ! Note that SHIFTBASE sets the lower triangular part by copying
      ! the upper triangular part, but here it does the opposite. There 
      ! seems not any particular reason to keep them different. It was
      ! probably an ad-hoc decision that Powell made when coding. 
      ! This part can be spared if we put a pair of parenthsis around 
      ! the two outter products as elaborated below.
      do j = 1, n
          bmat(1 : j - 1, npt + j) = bmat(j, npt + 1 : npt + j - 1)
      end do 
      !--------------MATRIX-VECTOR IMPLEMENTATION ENDS-----------------!

!---------------------A PROBABLY BETTER IMPLEMENTATION-----------------!
!-----!bmat = bmat + ( outprod(v1, vlag) + outprod(v2, w) ) !----------!
      ! The only difference from the previous matrix-vector 
      ! implementation is the parentheses.
      ! Note that the update is naturally symmetric thanks to the
      ! commutativity of floating point addition. We do not take this
      ! implementation for the moment to produce the same results as
      ! Powell's code, but we should take it in future versions.
!---------------------A PROBABLY BETTER IMPLEMENTATION ENDS------------!
       
      return

      end subroutine update
