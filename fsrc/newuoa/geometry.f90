module geometry_mod
!--------------------------------------------------------------------------------------------------!
! This module contains subroutines concerning the geometry-improving of the interpolation set XPT.
!
! Coded by Zaikun ZHANG (www.zhangzk.net) based on Powell's Fortran 77 code and the NEWUOA paper.
!
! Started: July 2020
!
! Last Modified: Wednesday, November 03, 2021 PM10:44:39
!--------------------------------------------------------------------------------------------------!

implicit none
private
public :: setdrop_tr, geostep


contains


function setdrop_tr(idz, kopt, tr_success, bmat, d, delta, rho, xpt, zmat) result(knew)
!--------------------------------------------------------------------------------------------------!
! This subroutine sets KNEW to the index of the interpolation point to be deleted AFTER A TRUST
! REGION STEP. KNEW will be set in a way ensuring that the geometry of XPT is "optimal" after
! XPT(:, KNEW) is replaced by XNEW = XOPT + D, where D is the trust-region step.
! N.B.:
! 1. If TR_SUCCESS = TRUE, then KNEW > 0 so that XNEW is included into XPT. Otherwise, it is a bug.
! 2. If TR_SUCCESS = FALSE, then KNEW /= KOPT so that XPT(:, KOPT) stays. Otherwise, it is a bug.
! 3. It is tempting to take the function value into consideration when defining KNEW, for example,
! set KNEW so that FVAL(KNEW) = MAX(FVAL) as long as F(XNEW) < MAX(FVAL), unless there is a better
! choice. However, this is not a good idea, because the definition of KNEW should benefit the
! quality of the model that interpolates f at XPT. A set of points with low function values is not
! necessarily a good interplolation set. In contrast, a good interpolation set needs to include
! points with relatively high function values; otherwise, the interpolant will unlikely reflect the
! landscape of the function sufficiently.
!--------------------------------------------------------------------------------------------------!

! Generic modules
use, non_intrinsic :: consts_mod, only : RP, IK, ONE, ZERO, TENTH, DEBUGGING
use, non_intrinsic :: debug_mod, only : assert
use, non_intrinsic :: infnan_mod, only : is_nan, is_finite
use, non_intrinsic :: linalg_mod, only : issymmetric

! Solver-specific modules
use, non_intrinsic :: vlagbeta_mod, only : calvlag, calbeta

implicit none

! Inputs
integer(IK), intent(in) :: idz
integer(IK), intent(in) :: kopt
logical, intent(in) :: tr_success
real(RP), intent(in) :: bmat(:, :)  ! BMAT(N, NPT + N)
real(RP), intent(in) :: d(:)
real(RP), intent(in) :: delta
real(RP), intent(in) :: rho
real(RP), intent(in) :: xpt(:, :)   ! XPT(N, NPT)
real(RP), intent(in) :: zmat(:, :)  ! ZMAT(NPT, NPT - N - 1)

! Outputs
integer(IK) :: knew

! Local variables
character(len=*), parameter :: srname = 'SETDROP_TR'
integer(IK) :: n
integer(IK) :: npt
real(RP) :: beta
real(RP) :: hdiag(size(zmat, 1))
real(RP) :: sigma(size(xpt, 2))
real(RP) :: vlag(size(xpt, 1) + size(xpt, 2))
real(RP) :: xdist(size(xpt, 2))

! Sizes
n = int(size(xpt, 1), kind(npt))
npt = int(size(xpt, 2), kind(npt))

! Preconditions
if (DEBUGGING) then
    call assert(n >= 1, 'N >= 1', srname)
    call assert(npt >= 3, 'NPT >= 3', srname)
    call assert(idz >= 1 .and. idz <= size(zmat, 2) + 1, '1 <= IDZ <= NPT - N', srname)
    call assert(kopt >= 1 .and. kopt <= npt, '1 <= KOPT <= NPT', srname)
    call assert(delta >= rho .and. rho > ZERO, 'DETLA >= RHO > 0', srname)
    call assert(size(d) == n, 'SIZE(D) == N', srname)
    call assert(all(is_finite(d)), 'D is finite', srname)
    call assert(size(bmat, 1) == n .and. size(bmat, 2) == npt + n, 'SIZE(BMAT)==[N, NPT+N]', srname)
    call assert(issymmetric(bmat(:, npt + 1:npt + n)), 'BMAT(:, NPT+1:NPT+N) is symmetric', srname)
    call assert(size(zmat, 1) == npt .and. size(zmat, 2) >= 1, &
        & 'SIZE(ZMAT, 1) == NPT, SIZE(ZMAT, 2) >= 1', srname)
end if

!====================!
! Calculation starts !
!====================!

! Calculate VLAG and BETA for D.
vlag = calvlag(idz, kopt, bmat, d, xpt, zmat)
beta = calbeta(idz, kopt, bmat, d, xpt, zmat)

! Calculate the distance between the interpolation points and the optimal point up to now.
if (tr_success) then
    xdist = sqrt(sum((xpt - spread(xpt(:, kopt) + d, dim=2, ncopies=npt))**2, dim=1))
else
    xdist = sqrt(sum((xpt - spread(xpt(:, kopt), dim=2, ncopies=npt))**2, dim=1))
end if

hdiag = -sum(zmat(:, 1:idz - 1)**2, dim=2) + sum(zmat(:, idz:size(zmat, 2))**2, dim=2)
sigma = abs(beta * hdiag + vlag(1:npt)**2)
sigma = sigma * max(ONE, xdist / max(TENTH * delta, rho))**6
if (.not. tr_success) then
    ! If the new F is not better than FVAL(KOPT), we set SIGMA(KOPT) = -1 to avoid KNEW = KOPT.
    sigma(kopt) = -ONE
end if

! KNEW = 0 by default. It cannot be removed, as KNEW may not be set below in some cases, e.g., when
! TR_SUCCESS = FALSE and MAXVAL(SIGMA) <= 1.
knew = 0_IK

! See (7.5) of the NEWUOA paper for the following definition of KNEW.
if (any(sigma > ONE) .or. (tr_success .and. any(.not. is_nan(sigma)))) then
    knew = int(maxloc(sigma, mask=(.not. is_nan(sigma)), dim=1), kind(knew))
end if

! Powell's code does not include the following instructions. With Powell's code, if SIGMA consists
! of only NaN, then KNEW can be 0 even when RATIO > 0.
if (tr_success .and. knew <= 0) then
    knew = int(maxloc(xdist, mask=(.not. is_nan(xdist)), dim=1), kind(knew))
end if

!====================!
!  Calculation ends  !
!====================!

! Postconditions
if (DEBUGGING) then
    call assert(knew >= 0 .and. knew <= npt, '0 <= KNEW <= NPT', srname)
    ! KNEW >= 1 when TR_SUCCESS = TRUE unless NaN occurs in XDIST, which should not happen if the
    ! starting point does not contain NaN and the trust-region/geometry steps never contain NaN.
    call assert(knew >= 1 .or. .not. tr_success, 'KNEW >= 1 unless TR_SUCCESS = FALSE', srname)
    call assert(knew /= kopt .or. tr_success, 'KNEW /= KOPT unless TR_SUCCESS = TRUE', srname)
end if

end function setdrop_tr


function geostep(idz, knew, kopt, bmat, delbar, xpt, zmat) result(d)
!--------------------------------------------------------------------------------------------------!
! This subroutine finds a step D such that the geometry of the interpolation set is improved when
! XPT(:, KNEW) is changed to XOPT + D, where XOPT = XPT(:, KOPT)
!
! N is the number of variables.
! NPT is the number of interpolation equations.
! XPT contains the current interpolation points.
! BMAT provides the last N ROWs of H.
! ZMAT and IDZ give a factorization of the first NPT by NPT sub-matrix of H.
! KNEW is the index of the interpolation point to be dropped.
! DELBAR is the trust region bound for the geometry step
! D will be set to the step from X to the new point.
!--------------------------------------------------------------------------------------------------!

! Generic modules
use, non_intrinsic :: consts_mod, only : RP, IK, ZERO, ONE, TWO, DEBUGGING
use, non_intrinsic :: debug_mod, only : assert
use, non_intrinsic :: infnan_mod, only : is_finite
use, non_intrinsic :: linalg_mod, only : inprod, issymmetric, norm

! Solver-specific modules
use, non_intrinsic :: vlagbeta_mod, only : calvlag, calbeta

implicit none

! Inputs
integer(IK), intent(in) :: idz
integer(IK), intent(in) :: knew
integer(IK), intent(in) :: kopt
real(RP), intent(in) :: bmat(:, :)  ! BMAT(N, NPT + N)
real(RP), intent(in) :: delbar
real(RP), intent(in) :: xpt(:, :)   ! XPT(N, NPT)
real(RP), intent(in) :: zmat(:, :)  ! ZMAT(NPT, NPT - N - 1)

! Outputs
real(RP) :: d(size(xpt, 1))     ! D(N)

! Local variables
character(len=*), parameter :: srname = 'GEOSTEP'
integer(IK) :: n
integer(IK) :: npt
real(RP) :: alpha
real(RP) :: absden
real(RP) :: beta
real(RP) :: vlag(size(xpt, 1) + size(xpt, 2))
real(RP) :: xopt(size(xpt, 1))
real(RP) :: zknew(size(zmat, 2))

! Sizes
n = int(size(xpt, 1), kind(n))
npt = int(size(xpt, 2), kind(npt))

! Preconditions
if (DEBUGGING) then
    call assert(n >= 1, 'N >= 1', srname)
    call assert(npt >= n + 2, 'NPT >= N + 2', srname)
    call assert(idz >= 1 .and. idz <= npt - n, '1 <= IDZ <= NPT - N', srname)
    call assert(knew >= 1 .and. knew <= npt, '1 <= KNEW <= NPT', srname)
    call assert(kopt >= 1 .and. kopt <= npt, '1 <= KOPT <= NPT', srname)
    call assert(knew /= kopt, 'KNEW /= KOPT', srname)
    call assert(size(bmat, 1) == n .and. size(bmat, 2) == npt + n, 'SIZE(BMAT)==[N, NPT+N]', srname)
    call assert(issymmetric(bmat(:, npt + 1:npt + n)), 'BMAT(:, NPT+1:NPT+N) is symmetric', srname)
    call assert(delbar > ZERO, 'DELBAR > 0', srname)
    call assert(all(is_finite(xpt)), 'XPT is finite', srname)
    call assert(size(zmat, 1) == npt .and. size(zmat, 2) == npt - n - 1, &
        & 'SIZE(ZMAT) == [NPT, NPT - N - 1]', srname)
end if

!====================!
! Calculation starts !
!====================!

xopt = xpt(:, kopt)  ! Read XOPT.

d = biglag(idz, knew, bmat, delbar, xopt, xpt, zmat)

! ALPHA is the KNEW-th diagonal entry of H.
zknew = zmat(knew, :)
zknew(1:idz - 1) = -zknew(1:idz - 1)
alpha = inprod(zmat(knew, :), zknew)

! Calculate VLAG and BETA for D. Indeed, VLAG(NPT + 1 : NPT + N) will not be used.
vlag = calvlag(idz, kopt, bmat, d, xpt, zmat)
beta = calbeta(idz, kopt, bmat, d, xpt, zmat)

! If the cancellation in DENOM is unacceptable, then BIGDEN calculates an alternative model step D.
if (vlag(knew)**2 <= ZERO) then
    ! Powell's code does not check VLAG(KNEW)**2. VLAG(KNEW)** > 0 in theory, but it can be 0 due to
    ! rounding, which did happen in tests. If VLAG(KNEW) ** = 0, then BIGLAG fails, because BIGLAG
    ! should maximize |VLAG(KNEW)|. Upon this failure, it is reasonable to call BIGDEN.
    absden = -ONE
else
    absden = abs(ONE + alpha * beta / vlag(knew)**2)
end if
if (absden <= 0.8_RP) then
    d = bigden(idz, knew, kopt, bmat, d, xpt, zmat)
end if

!====================!
!  Calculation ends  !
!====================!

! Postconditions
if (DEBUGGING) then
    call assert(all(is_finite(d)), 'D is finite', srname)
    ! Due to rounding, it may happen that |D| > DELTA, but |D| > 2*DELTA is highly improbable.
    call assert(norm(d) <= TWO * delbar, 'norm(D) <= 2*DELTA', srname)
end if

end function geostep


function biglag(idz, knew, bmat, delbar, x, xpt, zmat) result(d)
!--------------------------------------------------------------------------------------------------!
! This subroutine calculates a D by approximately solving
!
! max |LFUNC(X + D)|, subject to ||D|| <= DELBAR,
!
! where LFUNC is the KNEW-th Lagrange function. See Section 6 of the NEWUOA paper.
!--------------------------------------------------------------------------------------------------!

! Generic modules
use, non_intrinsic :: consts_mod, only : RP, IK, ZERO, ONE, TWO, HALF, QUART, TENTH, PI, EPS, DEBUGGING
use, non_intrinsic :: debug_mod, only : assert
use, non_intrinsic :: infnan_mod, only : is_finite
use, non_intrinsic :: linalg_mod, only : Ax_plus_y, inprod, matprod, issymmetric, norm

implicit none

! Inputs
integer(IK), intent(in) :: idz
integer(IK), intent(in) :: knew
real(RP), intent(in) :: bmat(:, :)  ! BMAT(N, NPT + N)
real(RP), intent(in) :: delbar
real(RP), intent(in) :: x(:)        ! X(N)
real(RP), intent(in) :: xpt(:, :)   ! XPT(N, NPT)
real(RP), intent(in) :: zmat(:, :)  ! ZMAT(NPT, NPT - N - 1)

! Outputs
real(RP) :: d(size(xpt, 1))       ! D(N)

! Local variables
character(len=*), parameter :: srname = 'BIGLAG'
integer(IK) :: i
integer(IK) :: isav
integer(IK) :: iter
integer(IK) :: iu
integer(IK) :: maxiter
integer(IK) :: n
integer(IK) :: npt
real(RP) :: angle
real(RP) :: cf(5)
real(RP) :: cth
real(RP) :: dd
real(RP) :: dhd
real(RP) :: dold(size(x))
real(RP) :: dunit(size(x))
real(RP) :: gc(size(x))
real(RP) :: gd(size(x))
real(RP) :: gg
real(RP) :: hcol(size(xpt, 2))
real(RP) :: s(size(x))
real(RP) :: scaling
real(RP) :: sp
real(RP) :: ss
real(RP) :: step
real(RP) :: sth
real(RP) :: t
real(RP) :: tau
real(RP) :: taua
real(RP) :: taub
real(RP) :: taubeg
real(RP) :: taumax
real(RP) :: tauold
real(RP) :: tol
real(RP) :: unitang
real(RP) :: w(size(x))
real(RP) :: zknew(size(zmat, 2))

! Sizes
n = int(size(xpt, 1), kind(n))
npt = int(size(xpt, 2), kind(npt))

! Preconditions
if (DEBUGGING) then
    call assert(n >= 1, 'N >= 1', srname)
    call assert(npt >= n + 2, 'NPT >= N + 2', srname)
    call assert(idz >= 1 .and. idz <= npt - n, '1 <= IDZ <= NPT - N', srname)
    call assert(knew >= 1 .and. knew <= npt, '1 <= KNEW <= NPT', srname)
    call assert(size(bmat, 1) == n .and. size(bmat, 2) == npt + n, 'SIZE(BMAT)==[N, NPT+N]', srname)
    call assert(issymmetric(bmat(:, npt + 1:npt + n)), 'BMAT(:, NPT+1:NPT+N) is symmetric', srname)
    call assert(delbar > ZERO, 'DELBAR > 0', srname)
    call assert(size(x) == n .and. all(is_finite(x)), 'SIZE(X) == N, X is finite', srname)
    call assert(all(is_finite(xpt)), 'XPT is finite', srname)
    call assert(size(zmat, 1) == npt .and. size(zmat, 2) == npt - n - 1, &
        & 'SIZE(ZMAT) == [NPT, NPT - N - 1]', srname)
end if

!====================!
! Calculation starts !
!====================!

! Set HCOL to the leading NPT elements of the KNEW-th column of H.
zknew = zmat(knew, :)
zknew(1:idz - 1) = -zknew(1:idz - 1)
hcol = matprod(zmat, zknew)

! Set the unscaled initial direction D. Form the gradient of LFUNC at X, and multiply D by the
! Hessian of LFUNC.
d = xpt(:, knew) - x
dd = inprod(d, d)

gd = matprod(xpt, hcol * matprod(d, xpt))

!-----------------------------------------------------------------------!
!-----!gc = bmat(:, knew) + matprod(xpt, hcol*matprod(x, xpt)) !--------!
! The following line works numerically better than the last line (why?).
gc = Ax_plus_y(xpt, hcol * matprod(x, xpt), bmat(:, knew))
!-----------------------------------------------------------------------!

! Scale D and GD, with a sign change if needed. Set S to another vector in the initial 2-D subspace.
gg = inprod(gc, gc)
sp = inprod(d, gc)
dhd = inprod(d, gd)
scaling = delbar / sqrt(dd)
if (sp * dhd < ZERO) then
    scaling = -scaling
end if
t = ZERO
if (sp**2 > 0.99_RP * dd * gg) then
    t = ONE
end if
tau = scaling * (abs(sp) + HALF * scaling * abs(dhd))
if (gg * delbar**2 < 1.0E-2_RP * tau**2) then
    t = ONE
end if
if (is_finite(sum(abs(scaling * d)))) then
    d = scaling * d
    gd = scaling * gd
    s = gc + t * gd
    maxiter = n
else
    maxiter = 0_IK  ! Return immediately to avoid producing a D containing NaN/Inf.
end if

! Begin the iteration by overwriting S with a vector that has the required length and direction,
! except that termination occurs if the given D and S are nearly parallel.
! TOL is the tolerance for telling whether S and D are nearly parallel. In Powell's code, the
! tolerance is 1.0D-4. We adapt it to the following value in case single precision is in use.
tol = min(1.0E-1_RP, max(EPS**QUART, 1.0E-4_RP))
do iter = 1, maxiter

    !----------------------------------------------------------------------------------------------!
    !!--------------------------------------------------!
    !!ds = inprod(d, s)
    !!ss = inprod(s, s)
    !!if (dd * ss - ds**2 <= 1.0E-8_RP * dd * ss) then
    !!    exit
    !!end if
    !!denom = sqrt(dd * ss - ds**2)
    !!s = (dd * s - ds * d) / denom
    !!--------------------------------------------------!
    ! The above is Powell's code. In precise arithmetic, INPROD(S, D) = 0 and |S| = |D|. However,
    ! when DD*SS - DS**2 is tiny, the error in S can be large and hence damage these inequalities
    ! significantly. This did happen in tests, especially when using the single precision. We
    ! calculate S as below. It did improve the performance of NEWUOA in our test.
    !----------------------------------------------------------------------------------------------!

    ss = inprod(s, s)
    dunit = d / norm(d)  ! Normalization seems to stabilize the projection below.
    s = s - inprod(s, dunit) * dunit
    ! N.B.:
    ! 1. The condition |S|<=TOL*SQRT(SS) below is equivalent to DS^2>=(1-TOL^2)*DD*SS in theory. As
    ! shown above, Powell's code triggers an exit if DS^2>=(1-1.0E-8)*DD*SS. So our condition is the
    ! same except that we take the machine epsilon into account in case single precision is in use.
    ! 2. The condition below should be non-strict so that |S| = 0 can trigger the exit.
    if (norm(s) <= tol * sqrt(ss)) then
        exit
    end if
    s = (s / norm(s)) * norm(d)
    ! In precise arithmetic, INPROD(S, D) = 0 and |S| = |D| = DELBAR.
    if (abs(inprod(d, s)) >= TENTH * norm(d) * norm(s) .or. norm(s) >= TWO * delbar) then
        exit
    end if

    w = matprod(xpt, hcol * matprod(s, xpt))

    ! Calculate the coefficients of the objective function on the circle, beginning with the
    ! multiplication of S by the second derivative matrix.
    cf(1) = inprod(s, w)
    cf(2) = inprod(d, gc)
    cf(3) = inprod(s, gc)
    cf(4) = inprod(d, gd)
    cf(5) = inprod(s, gd)
    cf(1) = HALF * cf(1)
    cf(4) = HALF * cf(4) - cf(1)

    ! Seek the value of the angle that maximizes |TAU|.
    taubeg = cf(1) + cf(2) + cf(4)
    taumax = taubeg
    tauold = taubeg
    isav = 0_IK
    iu = 49_IK
    unitang = (TWO * PI) / real(iu + 1, RP)

    do i = 1, iu
        angle = real(i, RP) * unitang
        cth = cos(angle)
        sth = sin(angle)
        tau = cf(1) + (cf(2) + cf(4) * cth) * cth + (cf(3) + cf(5) * cth) * sth
        if (abs(tau) > abs(taumax)) then
            taumax = tau
            isav = i
            taua = tauold
        else if (i == isav + 1) then
            taub = tau
        end if
        tauold = tau
    end do

    if (isav == 0) then
        taua = tau
    end if
    if (isav == iu) then
        taub = taubeg
    end if
    if (abs(taua - taub) > ZERO) then
        taua = taua - taumax
        taub = taub - taumax
        step = HALF * (taua - taub) / (taua + taub)
    else
        step = ZERO
    end if
    angle = unitang * (real(isav, RP) + step)

    ! Calculate the new D and GD. Then test for convergence.
    cth = cos(angle)
    sth = sin(angle)
    tau = cf(1) + (cf(2) + cf(4) * cth) * cth + (cf(3) + cf(5) * cth) * sth
    dold = d
    d = cth * d + sth * s

    ! Exit in case of Inf/NaN in D.
    if (.not. is_finite(sum(abs(d)))) then
        d = dold
        exit
    end if

    gd = cth * gd + sth * w
    s = gc + gd
    if (abs(tau) <= 1.1_RP * abs(taubeg)) then
        exit
    end if
end do

!====================!
!  Calculation ends  !
!====================!

! Postconditions
if (DEBUGGING) then
    call assert(all(is_finite(d)), 'D is finite', srname)
    ! Due to rounding, it may happen that |D| > DELBAR, but |D| > 2*DELBAR is highly improbable.
    call assert(norm(d) <= TWO * delbar, 'NORM(D) <= 2*DELBAR', srname)
end if

end function biglag


function bigden(idz, knew, kopt, bmat, d0, xpt, zmat) result(d)
!--------------------------------------------------------------------------------------------------!
! BIGDEN calculates a D by approximately solving
!
! max |SIGMA(XOPT + D)|, subject to ||D|| <= DELBAR,
!
! where SIGMA is the denominator sigma in the updating formula (4.11)--(4.12) for H, which is the
! inverse of the coefficient matrix for the interplolation system (see (3.12)). Indeed, each column
! of H corresponds to a Lagrange basis function of the interpolation problem.  See Section 6 of the
! NEWUOA paper.
! N.B.:
! In Powell's code, BIGDEN calculates also the VLAG and BETA for the selected D. Here, to reduce the
! coupling of code, we return only D but compute VLAG and BETA outside by calling VLAGBETA. It makes
! no difference mathematically, but the computed VLAG/BETA will change slightly due to rounding.
!--------------------------------------------------------------------------------------------------!

! Generic modules
use, non_intrinsic :: consts_mod, only : RP, IK, ZERO, ONE, TWO, HALF, TENTH, QUART, PI, EPS, DEBUGGING
use, non_intrinsic :: debug_mod, only : assert
use, non_intrinsic :: infnan_mod, only : is_finite
use, non_intrinsic :: linalg_mod, only : inprod, matprod, issymmetric, norm

implicit none

! Inputs
integer(IK), intent(in) :: idz
integer(IK), intent(in) :: knew
integer(IK), intent(in) :: kopt
real(RP), intent(in) :: bmat(:, :)  ! BMAT(N, NPT+N)
real(RP), intent(in) :: d0(:)
real(RP), intent(in) :: xpt(:, :)   ! XPT(N, NPT)
real(RP), intent(in) :: zmat(:, :)  ! ZMAT(NPT, NPT - N - 1)

! Outputs
real(RP) :: d(size(xpt, 1))     ! D(N)

! Local variable
character(len=*), parameter :: srname = 'BIGDEN'
integer(IK) :: i
integer(IK) :: isav
integer(IK) :: iter
integer(IK) :: iu
integer(IK) :: j
integer(IK) :: jc
integer(IK) :: k
integer(IK) :: n
integer(IK) :: npt
integer(IK) :: nw
real(RP) :: alpha
real(RP) :: angle
real(RP) :: dd
real(RP) :: den(9)
real(RP) :: dena
real(RP) :: denb
real(RP) :: denex(9)
real(RP) :: denmax
real(RP) :: denold
real(RP) :: denom
real(RP) :: denomold
real(RP) :: densav
real(RP) :: dold(size(xpt, 1))
real(RP) :: ds
real(RP) :: dstemp(size(xpt, 2))
real(RP) :: dtest
real(RP) :: dunit(size(xpt, 1))
real(RP) :: dxn
real(RP) :: hcol(size(xpt, 2))
real(RP) :: par(9)
real(RP) :: prod(size(xpt, 2) + size(xpt, 1), 5)
real(RP) :: s(size(xpt, 1))
real(RP) :: ss
real(RP) :: sstemp(size(xpt, 2))
real(RP) :: step
real(RP) :: tau
real(RP) :: tempa
real(RP) :: tempb
real(RP) :: tempc
real(RP) :: tol
real(RP) :: unitang
real(RP) :: v(size(xpt, 2))
real(RP) :: vlag(size(xpt, 1) + size(xpt, 2))
real(RP) :: w(size(xpt, 2) + size(xpt, 1), 5)
real(RP) :: wz(size(zmat, 2))
real(RP) :: x(size(xpt, 1))
real(RP) :: xd
real(RP) :: xnew(size(xpt, 1))
real(RP) :: xnsq
real(RP) :: xptemp(size(xpt, 1), size(xpt, 2))
real(RP) :: xs
real(RP) :: xsq
real(RP) :: zknew(size(zmat, 2))

! Sizes
n = int(size(xpt, 1), kind(n))
npt = int(size(xpt, 2), kind(npt))

! Preconditions
if (DEBUGGING) then
    call assert(n >= 1, 'N >= 1', srname)
    call assert(npt >= n + 2, 'NPT >= N + 2', srname)
    call assert(idz >= 1 .and. idz <= npt - n, '1 <= IDZ <= NPT - N', srname)
    call assert(knew >= 1 .and. knew <= npt, '1 <= KNEW <= NPT', srname)
    call assert(kopt >= 1 .and. kopt <= npt, '1 <= KOPT <= NPT', srname)
    call assert(knew /= kopt, 'KNEW /= KOPT', srname)
    call assert(size(bmat, 1) == n .and. size(bmat, 2) == npt + n, 'SIZE(BMAT)==[N, NPT+N]', srname)
    call assert(issymmetric(bmat(:, npt + 1:npt + n)), 'BMAT(:, NPT+1:NPT+N) is symmetric', srname)
    call assert(size(d0) == n .and. all(is_finite(d0)), 'SIZE(D0) == N, D0 is finite', srname)
    call assert(all(is_finite(xpt)), 'XPT is finite', srname)
    call assert(size(zmat, 1) == npt .and. size(zmat, 2) == npt - n - 1, &
        & 'SIZE(ZMAT) == [NPT, NPT - N - 1]', srname)
end if

!====================!
! Calculation starts !
!====================!

x = xpt(:, kopt) ! For simplicity, we use X to denote XOPT.

! Store the first NPT elements of the KNEW-th column of H in HCOL.
zknew = zmat(knew, :)
zknew(1:idz - 1) = -zknew(1:idz - 1)
hcol = matprod(zmat, zknew)
alpha = hcol(knew)

! The initial search direction D is taken from the last call of BIGLAG, and the initial S is set
! below, usually to the direction from X to X_KNEW, but a different direction to an interpolation
! point may be chosen, in order to prevent S from being nearly parallel to D.
d = d0
dd = inprod(d, d)
s = xpt(:, knew) - x
ds = inprod(d, s)
ss = inprod(s, s)
xsq = inprod(x, x)

if (.not. (ds**2 <= 0.99_RP * dd * ss)) then
    ! `.NOT. (A <= B)` differs from `A > B`.  The former holds iff A > B or {A, B} contains NaN.
    dtest = ds**2 / ss
    xptemp = xpt - spread(x, dim=2, ncopies=npt)
    !----------------------------------------------------------------!
    !---------!dstemp = matprod(d, xpt) - inprod(x, d) !-------------!
    dstemp = matprod(d, xptemp)
    !----------------------------------------------------------------!
    sstemp = sum((xptemp)**2, dim=1)

    dstemp(kopt) = TWO * ds + ONE
    sstemp(kopt) = ss
    k = int(minloc(dstemp**2 / sstemp, dim=1), kind(k))
    ! K can be 0 due to NaN. In that case, set K = KNEW. Otherwise, memory errors will occur.
    if (k == 0) then
        k = knew
    end if
    if ((.not. (dstemp(k)**2 / sstemp(k) >= dtest)) .and. k /= kopt) then
        ! `.NOT. (A >= B)` differs from `A < B`.  The former holds iff A < B or {A, B} contains NaN.
        ! Although unlikely, if NaN occurs, it may happen that K = KOPT.
        s = xpt(:, k) - x
    end if
end if

densav = ZERO

! Begin the iteration by overwriting S with a vector that has the required length and direction.

! TOL is the tolerance for telling whether S and D are nearly parallel. In Powell's code, the
! tolerance is 1.0D-4. We adapt it to the following value in case single precision is in use.
tol = min(1.0E-1_RP, max(EPS**QUART, 1.0E-4_RP))
do iter = 1, n

    !----------------------------------------------------------------------------------------------!
    !!--------------------------------------------!
    !!ds = inprod(d, s)
    !!ss = inprod(s, s)
    !!ssden = dd * ss - ds**2
    !!if (ssden < 1.0E-8_RP * dd * ss) then
    !    exit
    !end if
    !!s = (ONE / sqrt(ssden)) * (dd * s - ds * d)
    !!--------------------------------------------!
    ! The above is Powell's code. In precise arithmetic, INPROD(S, D) = 0 and |S| = |D|. However,
    ! when DD*SS - DS**2 is tiny, the error in S can be large and hence damage these inequalities
    ! significantly. This did happen in tests, especially when using the single precision. We
    ! calculate S as below. It did improve the performance of NEWUOA in our test.
    !----------------------------------------------------------------------------------------------!

    ss = inprod(s, s)
    dunit = d / norm(d)  ! Normalization seems to stabilize the projection below.
    s = s - inprod(s, dunit) * dunit
    ! N.B.:
    ! 1. The condition |S|<=TOL*SQRT(SS) below is equivalent to DS^2>=(1-TOL^2)*DD*SS in theory. As
    ! shown above, Powell's code triggers an exit if DS^2>=(1-1.0E-8)*DD*SS. So our condition is the
    ! same except that we take the machine epsilon into account in case single precision is in use.
    ! 2. The condition below should be non-strict so that |S| = 0 can trigger the exit.
    if (norm(s) <= tol * sqrt(ss)) then
        exit
    end if
    s = (s / norm(s)) * norm(d)
    ! In precise arithmetic, INPROD(S, D) = 0 and |S| = |D| = DELBAR = |D0|.
    if (abs(inprod(d, s)) >= TENTH * norm(d) * norm(s) .or. norm(s) >= TWO * norm(d0)) then
        exit
    end if

    xd = inprod(x, d)
    xs = inprod(x, s)

    ! Set the coefficients of the first two terms of BETA.
    tempa = HALF * xd * xd
    tempb = HALF * xs * xs
    den(1) = dd * (xsq + HALF * dd) + tempa + tempb
    den(2) = TWO * xd * dd
    den(3) = TWO * xs * dd
    den(4) = tempa - tempb
    den(5) = xd * xs
    den(6:9) = ZERO

    ! Put the coefficients of WCHECK in W.
    do k = 1, npt
        tempa = inprod(xpt(:, k), d)
        tempb = inprod(xpt(:, k), s)
        tempc = inprod(xpt(:, k), x)
        w(k, 1) = QUART * (tempa**2 + tempb**2)
        w(k, 2) = tempa * tempc
        w(k, 3) = tempb * tempc
        w(k, 4) = QUART * (tempa**2 - tempb**2)
        w(k, 5) = HALF * tempa * tempb
    end do
    w(npt + 1:npt + n, 1:5) = ZERO
    w(npt + 1:npt + n, 2) = d
    w(npt + 1:npt + n, 3) = s

    ! Put the coefficents of THETA*WCHECK in PROD.
    do jc = 1, 5
        wz = matprod(w(1:npt, jc), zmat)
        wz(1:idz - 1) = -wz(1:idz - 1)
        prod(1:npt, jc) = matprod(zmat, wz)

        nw = npt
        if (jc == 2 .or. jc == 3) then
            prod(1:npt, jc) = prod(1:npt, jc) + matprod(w(npt + 1:npt + n, jc), bmat(:, 1:npt))
            nw = npt + n
        end if
        prod(npt + 1:npt + n, jc) = matprod(bmat(:, 1:nw), w(1:nw, jc))
    end do

    ! Include in DEN the part of BETA that depends on THETA.
    do k = 1, npt + n
        par(1:5) = HALF * prod(k, 1:5) * w(k, 1:5)
        den(1) = den(1) - par(1) - sum(par(1:5))
        tempa = prod(k, 1) * w(k, 2) + prod(k, 2) * w(k, 1)
        tempb = prod(k, 2) * w(k, 4) + prod(k, 4) * w(k, 2)
        tempc = prod(k, 3) * w(k, 5) + prod(k, 5) * w(k, 3)
        den(2) = den(2) - tempa - HALF * (tempb + tempc)
        den(6) = den(6) - HALF * (tempb - tempc)
        tempa = prod(k, 1) * w(k, 3) + prod(k, 3) * w(k, 1)
        tempb = prod(k, 2) * w(k, 5) + prod(k, 5) * w(k, 2)
        tempc = prod(k, 3) * w(k, 4) + prod(k, 4) * w(k, 3)
        den(3) = den(3) - tempa - HALF * (tempb - tempc)
        den(7) = den(7) - HALF * (tempb + tempc)
        tempa = prod(k, 1) * w(k, 4) + prod(k, 4) * w(k, 1)
        den(4) = den(4) - tempa - par(2) + par(3)
        tempa = prod(k, 1) * w(k, 5) + prod(k, 5) * w(k, 1)
        tempb = prod(k, 2) * w(k, 3) + prod(k, 3) * w(k, 2)
        den(5) = den(5) - tempa - HALF * tempb
        den(8) = den(8) - par(4) + par(5)
        tempa = prod(k, 4) * w(k, 5) + prod(k, 5) * w(k, 4)
        den(9) = den(9) - HALF * tempa
    end do

    par(1:5) = HALF * prod(knew, 1:5)**2
    denex(1) = alpha * den(1) + par(1) + sum(par(1:5))
    tempa = TWO * prod(knew, 1) * prod(knew, 2)
    tempb = prod(knew, 2) * prod(knew, 4)
    tempc = prod(knew, 3) * prod(knew, 5)
    denex(2) = alpha * den(2) + tempa + tempb + tempc
    denex(6) = alpha * den(6) + tempb - tempc
    tempa = TWO * prod(knew, 1) * prod(knew, 3)
    tempb = prod(knew, 2) * prod(knew, 5)
    tempc = prod(knew, 3) * prod(knew, 4)
    denex(3) = alpha * den(3) + tempa + tempb - tempc
    denex(7) = alpha * den(7) + tempb + tempc
    tempa = TWO * prod(knew, 1) * prod(knew, 4)
    denex(4) = alpha * den(4) + tempa + par(2) - par(3)
    tempa = TWO * prod(knew, 1) * prod(knew, 5)
    denex(5) = alpha * den(5) + tempa + prod(knew, 2) * prod(knew, 3)
    denex(8) = alpha * den(8) + par(4) - par(5)
    denex(9) = alpha * den(9) + prod(knew, 4) * prod(knew, 5)

    ! Seek the value of the angle that maximizes the |DENOM|.
    denom = denex(1) + denex(2) + denex(4) + denex(6) + denex(8)
    denold = denom
    denmax = denom
    isav = 0_IK
    iu = 49_IK
    unitang = (TWO * PI) / real(iu + 1, RP)
    par(1) = ONE
    do i = 1, iu
        angle = real(i, RP) * unitang
        par(2) = cos(angle)
        par(3) = sin(angle)
        do j = 4, 8, 2
            par(j) = par(2) * par(j - 2) - par(3) * par(j - 1)
            par(j + 1) = par(2) * par(j - 1) + par(3) * par(j - 2)
        end do
        denomold = denom
        denom = inprod(denex(1:9), par(1:9))
        if (abs(denom) > abs(denmax)) then
            denmax = denom
            isav = i
            dena = denomold
        else if (i == isav + 1) then
            denb = denom
        end if
    end do
    if (isav == 0) then
        dena = denom
    end if
    if (isav == iu) then
        denb = denold
    end if
    if (abs(dena - denb) > ZERO) then
        dena = dena - denmax
        denb = denb - denmax
        step = HALF * (dena - denb) / (dena + denb)
    else
        step = ZERO
    end if
    angle = unitang * (real(isav, RP) + step)

    ! Calculate the new parameters of the denominator, the new VLAG vector and the new D. Then test
    ! for convergence.
    par(2) = cos(angle)
    par(3) = sin(angle)
    do j = 4, 8, 2
        par(j) = par(2) * par(j - 2) - par(3) * par(j - 1)
        par(j + 1) = par(2) * par(j - 1) + par(3) * par(j - 2)
    end do

    !beta = inprod(den(1:9), par(1:9))  ! Not needed since we do not return BETA.

    denmax = inprod(denex(1:9), par(1:9))

    vlag = matprod(prod(:, 1:5), par(1:5))

    tau = vlag(knew)

    dold = d
    d = par(2) * d + par(3) * s
    ! Exit in case of Inf/NaN in D.
    if (.not. is_finite(sum(abs(d)))) then
        d = dold
        exit
    end if

    dd = inprod(d, d)
    xnew = x + d
    dxn = inprod(d, xnew)
    xnsq = inprod(xnew, xnew)

    if (iter > 1) then
        densav = max(densav, denold)
    end if
    if (abs(denmax) <= 1.1_RP * abs(densav)) then
        exit
    end if
    densav = denmax

    ! Set S to HALF the gradient of the denominator with respect to D.
    s = tau * bmat(:, knew) + alpha * (dxn * x + xnsq * d - vlag(npt + 1:npt + n))
    v = matprod(xnew, xpt)
    v = (tau * hcol - alpha * vlag(1:npt)) * v
    s = s + matprod(xpt, v)
end do

!vlag(kopt) = vlag(kopt) + ONE  ! Not needed since we do not return VLAG.

!====================!
!  Calculation ends  !
!====================!

! Postconditions
if (DEBUGGING) then
    call assert(all(is_finite(d)), 'D is finite', srname)
    ! Due to rounding, it may happen that |D| > DELBAR = |D0|, but |D| > 2*DELBAR is highly improbable.
    call assert(norm(d) <= TWO * norm(d0), 'NORM(D) <= 2*DELBAR', srname)
end if

end function bigden


end module geometry_mod
