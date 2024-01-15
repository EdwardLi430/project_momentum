function value = m_bucket(m, m20, m40, m60, m80)
%M_BUCKET Summary of this function goes here
%   row is a table class 
if m< m20
    value='1';
elseif m> m20 && m<=m40
    value='2';
elseif m> m40 && m<=m60
    value='3';
elseif m> m60 && m<=m80
    value='4';
elseif m>= m80 
    value='5';
else
    value='6';
    
end